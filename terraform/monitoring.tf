resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.monitoring_namespace
  }
}

# Karpenter monitoring requires the Prometheus Operator CRDs
resource "helm_release" "prometheus_operator_crds" {
  namespace        = var.monitoring_namespace
  name             = "prometheus-operator-crds"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus-operator-crds"
  version          = "~> 14.0.0"
  create_namespace = false
  wait             = true
}


# Amazon Managed Service for Grafana
module "managed_grafana" {
  source = "terraform-aws-modules/managed-service-grafana/aws"

  # Workspace
  name                      = "${var.name}-grafana"
  description               = "Managed Grafana workspace for ${var.name}"
  account_access_type       = "CURRENT_ACCOUNT"
  authentication_providers  = ["AWS_SSO"]
  permission_type           = "SERVICE_MANAGED"
  data_sources              = ["CLOUDWATCH", "PROMETHEUS", "XRAY"]
  notification_destinations = ["SNS"]

  create_workspace      = true
  create_iam_role       = true
  create_security_group = true
  associate_license     = false
  license_type          = "ENTERPRISE_FREE_TRIAL"

  security_group_rules = {
    egress = {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Workspace API keys
  workspace_api_keys = {
    admin = {
      key_name        = "admin"
      key_role        = "ADMIN"
      seconds_to_live = 3600
    }
  }

  # Role associations
  role_associations = {
    "ADMIN" = {
      "user_ids" = ["01dbd590-e041-7037-85a4-31646453ee0a", "e1dbe5a0-d0b1-700d-3fe5-815968958634"]
    }
  }
}

resource "aws_prometheus_workspace" "cloudpipe" {
  alias = "${var.name}-prometheus"
}


resource "helm_release" "aws-for-fluent-bit" {
  name             = "aws-for-fluent-bit"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-for-fluent-bit"
  namespace        = var.monitoring_namespace
  create_namespace = false
  cleanup_on_fail  = true
  recreate_pods    = true

  values = [
    templatefile("${path.module}/helm-values/aws-for-fluent-bit/aws-for-fluent-bit-values.yaml",
      {
        # MUST hardcore the region below - using a variable causes it to be blank???
        region               = "us-east-2"
        cloudwatch_log_group = "/${var.name}/aws-fluentbit-logs"
        s3_bucket_name       = "brave-logs"
        cluster_name         = module.eks.cluster_name
    })
  ]
}

resource "helm_release" "aws-cloudwatch-metrics" {
  name             = "aws-cloudwatch-metrics"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-cloudwatch-metrics"
  namespace        = var.monitoring_namespace
  create_namespace = false
  cleanup_on_fail  = true
  recreate_pods    = true

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
}


# resource "helm_release" "aws-observability" {
#   name             = "amazon-cloudwatch"
#   repository       = "https://aws-observability.github.io/helm-charts"
#   chart            = "amazon-cloudwatch-observability"
#   namespace        = "amazon-cloudwatch"
#   create_namespace = true

#   set {
#     name  = "clusterName"
#     value = var.name
#   }
#   set {
#     name  = "region"
#     value = local.region
#   }
# }

# module "eks_container_insights" {
#   source                                     = "github.com/aws-observability/terraform-aws-observability-accelerator//modules/eks-container-insights"
#   eks_cluster_id                             = var.name
#   enable_amazon_eks_cw_observability         = true
#   create_cloudwatch_observability_irsa_role  = true
#   eks_oidc_provider_arn                      = module.eks.oidc_provider_arn
#   create_cloudwatch_application_signals_role = true
# }

data "aws_iam_policy" "cloudwatch_agent_server" {
  arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy" "amp_remote_write_access" {
  arn = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
}

# data "aws_iam_policy" "xray_write_access" {
#   arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
# }

module "irsa-adot-collector" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.52.2"

  create_role  = true
  role_name    = "opentelemetry-operator"
  provider_url = module.eks.cluster_oidc_issuer_url

  role_policy_arns = [
    data.aws_iam_policy.cloudwatch_agent_server.arn,
    data.aws_iam_policy.amp_remote_write_access.arn
  ]
  oidc_fully_qualified_subjects = ["system:serviceaccount:opentelemetry-operator-system:opentelemetry-operator"]
}

module "amp_iamproxy_ingest_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.22"

  role_name                                       = "amp-iamproxy-ingest-role"
  attach_amazon_managed_service_prometheus_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["opentelemetry-operator-system:amp-iamproxy-ingest-role"]
    }
  }
}

data "aws_eks_addon_version" "adot" {
  addon_name         = "adot"
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

resource "aws_eks_addon" "adot" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "adot"
  addon_version            = data.aws_eks_addon_version.adot.version
  service_account_role_arn = module.irsa-adot-collector.iam_role_arn
  # i.e., 'preserve' the custom value
  resolve_conflicts_on_update = "OVERWRITE"
}

# resource "kubectl_manifest" "otel_collector" {
#   yaml_body = templatefile("${path.module}/yamls/adot/otel-collector-prometheus.yaml",
#     {
#       region              = var.region
#       amp_remotewrite_url = "${aws_prometheus_workspace.cloudpipe.prometheus_endpoint}api/v1/remote_write"
#       namespace           = var.monitoring_namespace
#   })
# }
