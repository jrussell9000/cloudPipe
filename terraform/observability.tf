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

# Creating an IRSA for AMP metric ingestion
resource "aws_iam_role" "amp_ingestion" {
  name        = "amp-ingestion-role"
  description = "AMP metric ingestion role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "${module.eks.oidc_provider_arn}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # Compare the OIDC audience claim to ensure it's for this service account
            # Specify the SA namespace as described here: https://aws-otel.github.io/docs/getting-started/prometheus-remote-write-exporter/eks#editing-the-trust-policy
            "${module.eks.oidc_provider}:sub" = "system:serviceaccount:${kubernetes_service_account_v1.acwo_sa.metadata[0].name}:amp-iamproxy-ingest-service-account"
          }
        }
      }
    ]
  })
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

resource "aws_iam_role_policy_attachment" "amp_ingestion" {
  role       = aws_iam_role.amp_ingestion.name
  policy_arn = aws_iam_policy.amp_ingestion.arn
}

resource "kubernetes_service_account_v1" "amp_ingestion" {
  metadata {
    name      = "amp-iamproxy-ingest-service-account"
    namespace = kubernetes_namespace_v1.amazon_cloudwatch.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.amp_ingestion.arn
    }
  }
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

# Create CloudWatch service account (using default name: "cloudwatch-agent") and linking to IAM role
resource "kubernetes_service_account_v1" "acwo_sa" {
  metadata {
    name      = "cloudwatch-agent"
    namespace = kubernetes_namespace_v1.amazon_cloudwatch.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.acwo.arn
    }
  }
}

# Getting the latest version of the amazon-cloudwatch-observability EKS addon
data "aws_eks_addon_version" "acwo" {
  addon_name         = "amazon-cloudwatch-observability"
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

# Installing the ACWO add-on
resource "aws_eks_addon" "acwo" {
  cluster_name  = var.name
  addon_name    = data.aws_eks_addon_version.acwo.id
  addon_version = data.aws_eks_addon_version.acwo.version
  pod_identity_association {
    role_arn        = aws_iam_role.acwo.arn
    service_account = kubernetes_service_account_v1.acwo_sa.metadata[0].name
  }
  configuration_values = file("${path.module}/yamls/amazon-cloudwatch-observability/amazon-cloudwatch-observability-eksaddon-general-config-v2.yaml")

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
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

resource "aws_iam_role_policy_attachment" "grafana_amp_access_attachment" {
  role       = aws_iam_role.grafana_workspace_role.name
  policy_arn = aws_iam_policy.grafana_amp_access_policy.arn
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
