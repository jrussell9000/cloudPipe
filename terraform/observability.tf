#---------------------------------------------------------------
# Amazon Cloudwatch Observability
#---------------------------------------------------------------

# Create observability namespace
resource "kubernetes_namespace_v1" "amazon_cloudwatch" {
  metadata {
    name = "amazon-cloudwatch"
  }
}

# AMAZON MANAGED PROMETHEUS #
# https://docs.aws.amazon.com/prometheus/latest/userguide/set-up-irsa.html#set-up-irsa-ingest

# Create Amazon Managed Prometheus workspace
resource "aws_prometheus_workspace" "amp" {
  alias = "${var.name}-amp"
}

resource "aws_iam_policy" "amp_ingestion" {
  name = "AMPIngestionPolicy"
  path = "/"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "aps:RemoteWrite",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

# Managed Collectors

resource "aws_prometheus_scraper" "this" {
  source {
    eks {
      cluster_arn = module.eks.cluster_arn
      subnet_ids  = module.vpc.private_subnets
    }
  }

  destination {
    amp {
      workspace_arn = aws_prometheus_workspace.amp.arn
    }
  }

  scrape_configuration = <<EOT
global:
  scrape_interval: 30s
  external_labels:
    clusterArn: ${module.eks.cluster_arn}
scrape_configs:
  # pod metrics
  - job_name: pod_exporter
    kubernetes_sd_configs:
      - role: pod
  # container metrics
  - job_name: cadvisor
    scheme: https
    authorization:
      credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    kubernetes_sd_configs:
      - role: node
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
      - replacement: kubernetes.default.svc:443
        target_label: __address__
      - source_labels: [__meta_kubernetes_node_name]
        regex: (.+)
        target_label: __metrics_path__
        replacement: /api/v1/nodes/$1/proxy/metrics/cadvisor
  # apiserver metrics
  - bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    job_name: kubernetes-apiservers
    kubernetes_sd_configs:
    - role: endpoints
    relabel_configs:
    - action: keep
      regex: default;kubernetes;https
      source_labels:
      - __meta_kubernetes_namespace
      - __meta_kubernetes_service_name
      - __meta_kubernetes_endpoint_port_name
    scheme: https
  # kube proxy metrics
  - job_name: kube-proxy
    honor_labels: true
    kubernetes_sd_configs:
    - role: pod
    relabel_configs:
    - action: keep
      source_labels:
      - __meta_kubernetes_namespace
      - __meta_kubernetes_pod_name
      separator: '/'
      regex: 'kube-system/kube-proxy.+'
    - source_labels:
      - __address__
      action: replace
      target_label: __address__
      regex: (.+?)(:d+)?
      replacement: $1:10249
  - job_name: karpenter
    honor_labels: true
    kubernetes_sd_configs:
    - role: endpoints
      namespaces:
        names:
          - 'kube-system'
EOT
}

# AMAZON CLOUDWATCH OBSERVABILITY (ACWO) #

# Creating trust policy for EKS Pod Identity service to assume a role
data "aws_iam_policy_document" "acwo_assume_pod_identity" {
  statement {
    sid    = "AllowEksAuthToAssumeRoleForPodIdentity"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

# Creating an IAM role for the CloudWatch Agent and attaching the trust policy (assume_role)
resource "aws_iam_role" "acwo" {
  name               = "AmazonEKSCloudWatchAgentPodRole"
  assume_role_policy = data.aws_iam_policy_document.acwo_assume_pod_identity.json
}

resource "aws_iam_role_policy_attachment" "amp_remote_write_access" {
  role       = aws_iam_role.acwo.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
}

resource "aws_iam_role_policy_attachment" "amp_query_access" {
  role       = aws_iam_role.acwo.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess"
}

# Attaching the CloudWatchAgentServerPolicy to the role (required by CloudWatch Agent)
resource "aws_iam_role_policy_attachment" "acwo" {
  role       = aws_iam_role.acwo.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "helm_release" "amazon_cloudwatch_observability" {
  name             = "amazon-cloudwatch"
  repository       = "https://aws-observability.github.io/helm-charts"
  chart            = "amazon-cloudwatch-observability"
  namespace        = "amazon-cloudwatch"
  create_namespace = true
  wait             = false

  values = [file("${path.module}/helm-values/acwo/values.yaml")]
  set = [
    {
      name  = "clusterName"
      value = var.name
    },
    {
      name  = "region"
      value = var.region
    },
    {
      name  = "agent.otelConfig.exporters.prometheusremotewrite/cloudpipe.endpoint"
      value = "${aws_prometheus_workspace.amp.prometheus_endpoint}api/v1/remote_write"
    }
  ]
}

# AMAZON MANAGED GRAFANA #

# Create IAM Role for Grafana Workspace to Access AWS Services (incl. AMP)
data "aws_iam_policy_document" "grafana_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "grafana_workspace_role" {
  name               = "${var.name}-grafana-workspace-role"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume_role_policy.json
}

data "aws_iam_policy_document" "grafana_amp_access_policy" {

  depends_on = [aws_prometheus_workspace.amp]
  statement {
    sid    = "AllowGrafanaToQueryAMP"
    effect = "Allow"
    actions = [
      "aps:ListWorkspaces",
      "aps:QueryMetrics",
      "aps:GetLabels",
      "aps:GetSeries",
      "aps:GetMetricMetadata",
      "aps:DescribeWorkspace" # Recommended for SigV4 setup
    ]
    resources = [
      aws_prometheus_workspace.amp.arn # Grant access ONLY to the created AMP workspace
    ]

  }
  # This permission needs an asterisk for resources
  statement {
    sid    = "AllowGrafanaToListAMPWorkspaces"
    effect = "Allow"
    actions = [
      "aps:ListWorkspaces"
    ]
    resources = ["*"]
  }
  # Allow access to X-Ray if you plan to use it as a data source
  statement {
    sid    = "AllowGrafanaXRayAccess"
    effect = "Allow"
    actions = [
      "xray:BatchGetTraces",
      "xray:GetTraceSummaries",
      "xray:GetTraceGraph",
      "xray:GetGroups",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
      "xray:GetSamplingStatisticSummaries"
    ]
    resources = ["*"] # X-Ray permissions are typically broad
  }
}

resource "aws_iam_policy" "grafana_amp_access_policy" {
  name        = "${var.name}-grafana-amp-access-policy"
  description = "Allows Grafana workspace to query the specific AMP workspace"
  policy      = data.aws_iam_policy_document.grafana_amp_access_policy.json
}


data "aws_iam_policy_document" "grafana_cloudwatch_access" {
  statement {
    sid    = "AllowReadingMetricsFromCloudWatch"
    effect = "Allow"
    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetInsightRuleReport"
    ]
    resources = ["*"]
  }
  statement {
    sid       = "AllowReadingResourceMetricsFromPerformanceInsights"
    effect    = "Allow"
    actions   = ["pi:GetResourceMetrics"]
    resources = ["*"]
  }
  statement {
    sid    = "AllowReadingLogsFromCloudWatch"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:GetLogEvents"
    ]
    resources = ["*"]
  }
  statement {
    sid       = "AllowReadingTagsInstancesRegionsFromEC2"
    effect    = "Allow"
    actions   = ["ec2:DescribeTags", "ec2:DescribeInstances", "ec2:DescribeRegions"]
    resources = ["*"]
  }
  statement {
    sid       = "AllowReadingResourcesForTags"
    effect    = "Allow"
    actions   = ["tag:GetResources"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "grafana_cloudwatch_access" {
  name        = "${var.name}-grafana-cloudwatch-access-policy"
  description = "Allows Grafana to access a Cloudwatch data source"
  policy      = data.aws_iam_policy_document.grafana_cloudwatch_access.json
}

resource "aws_iam_role_policy_attachment" "grafana_amp_access_attachment" {
  role       = aws_iam_role.grafana_workspace_role.name
  policy_arn = aws_iam_policy.grafana_amp_access_policy.arn
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch_access_attachment" {
  role       = aws_iam_role.grafana_workspace_role.name
  policy_arn = aws_iam_policy.grafana_cloudwatch_access.arn
}

resource "aws_grafana_workspace" "amg" {
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]       # Or ["SAML"]
  permission_type          = "SERVICE_MANAGED" # Allow AWS to manage the necessary permissions
  name                     = "${var.name}-grafana-workspace"
  role_arn                 = aws_iam_role.grafana_workspace_role.arn
  description              = "Grafana workspace for EKS monitoring (${var.name})"
  data_sources             = ["PROMETHEUS", "CLOUDWATCH"]

  # Optional: Configure VPC connection if needed for private data source
  # vpc_configuration {
  #   security_group_ids = ["sg-xxxxxxxxxxxxxxxxx"]
  #   subnet_ids         = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-yyyyyyyyyyyyyyyyy"]
  # }

  # Ensure AMP workspace exists before Grafana tries to potentially configure access to it
  depends_on = [
    aws_prometheus_workspace.amp,
    aws_iam_role_policy_attachment.grafana_amp_access_attachment
  ]
}

resource "aws_grafana_role_association" "amg" {
  role         = "ADMIN"
  user_ids     = ["01dbd590-e041-7037-85a4-31646453ee0a", "e1dbe5a0-d0b1-700d-3fe5-815968958634"]
  workspace_id = aws_grafana_workspace.amg.id
}

resource "aws_grafana_workspace_service_account" "amg" {
  name         = "${var.name}-admin"
  grafana_role = "ADMIN"
  workspace_id = aws_grafana_workspace.amg.id
}

resource "aws_grafana_workspace_service_account_token" "amg" {
  name               = "${var.name}-amg-key"
  service_account_id = aws_grafana_workspace_service_account.amg.service_account_id
  seconds_to_live    = 3600
  workspace_id       = aws_grafana_workspace.amg.id
}

#---------------------------------------------------------------
# Prometheus Operator CRDs
#---------------------------------------------------------------
resource "helm_release" "prometheus_crds" {

  name             = "prometheus-operator-crds"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus-operator-crds"
  version          = "19.0.0"
  namespace        = "prometheus"
  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true
}

#---------------------------------------------------------------
# Kubecost
#---------------------------------------------------------------

module "kubecost_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "kubecost-cost-analyzer-amp"

  additional_policy_arns = {
    "AmazonPrometheusQueryAccess"       = "arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess"
    "AmazonPrometheusRemoteWriteAccess" = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
  }

  # Add EBS permissions policy here
  associations = {
    kubecost-cost-analyzer-amp = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kubecost"
      service_account = "kubecost-cost-analyzer-amp"
    }
  }
}

resource "helm_release" "kubecost" {

  name             = "kubecost"
  repository       = "https://kubecost.github.io/cost-analyzer/"
  chart            = "cost-analyzer"
  namespace        = "kubecost"
  create_namespace = true
  cleanup_on_fail  = true
  recreate_pods    = true
  values = [
    templatefile("${path.module}/helm-values/kubecost/values-eks-cost-monitoring.yaml",
      {
        region           = var.region
        cluster_name     = var.name
        amp_workspace_id = aws_prometheus_workspace.amp.id
      }
    )
  ]

  depends_on = [helm_release.aws_ebs_csi_driver,
    helm_release.cert-manager,
  module.kubecost_pod_identity]
}


