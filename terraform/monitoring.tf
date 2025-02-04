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


# resource "helm_release" "aws-for-fluent-bit" {
#   name             = "aws-for-fluent-bit"
#   repository       = "https://aws.github.io/eks-charts"
#   chart            = "aws-for-fluent-bit"
#   namespace        = "monitoring"
#   create_namespace = true
#   cleanup_on_fail  = true
#   recreate_pods    = true

#   values = [
#     templatefile("${path.module}/helm-values/aws-for-fluent-bit/aws-for-fluent-bit-values.yaml",
#       {
#         # MUST hardcore the region below - using a variable causes it to be blank???
#         region               = "us-east-2"
#         cloudwatch_log_group = "/${var.name}/aws-fluentbit-logs"
#         s3_bucket_name       = "brave-logs"
#         cluster_name         = module.eks.cluster_name
#     })
#   ]
# }

resource "helm_release" "aws-observability" {
  name             = "amazon-cloudwatch"
  repository       = "https://aws-observability.github.io/helm-charts"
  chart            = "amazon-cloudwatch-observability"
  namespace        = "amazon-cloudwatch"
  create_namespace = true

  set {
    name  = "clusterName"
    value = var.name
  }
  set {
    name  = "region"
    value = local.region
  }
}

# module "eks_container_insights" {
#   source                                     = "github.com/aws-observability/terraform-aws-observability-accelerator//modules/eks-container-insights"
#   eks_cluster_id                             = var.name
#   enable_amazon_eks_cw_observability         = true
#   create_cloudwatch_observability_irsa_role  = true
#   eks_oidc_provider_arn                      = module.eks.oidc_provider_arn
#   create_cloudwatch_application_signals_role = true
# }

# data "aws_iam_policy" "cloudwatch_agent_server" {
#   arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
# }

# data "aws_iam_policy" "amp_remote_write_access" {
#   arn = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
# }

# data "aws_iam_policy" "xray_write_access" {
#   arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
# }

# module "irsa-adot-collector" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
#   version = "5.52.2"

#   create_role  = true
#   role_name    = "opentelemetry-operator"
#   provider_url = module.eks.cluster_oidc_issuer_url

#   role_policy_arns = [
#     data.aws_iam_policy.cloudwatch_agent_server.arn,
#     data.aws_iam_policy.amp_remote_write_access.arn
#   ]
#   oidc_fully_qualified_subjects = ["system:serviceaccount:opentelemetry-operator-system:opentelemetry-operator"]
# }

# module "irsa-adot-col-prom-metrics" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
#   version = "5.52.2"

#   create_role  = true
#   role_name    = "adot-col-prom-metrics"
#   provider_url = module.eks.cluster_oidc_issuer_url

#   role_policy_arns = [
#     data.aws_iam_policy.cloudwatch_agent_server.arn,
#     data.aws_iam_policy.amp_remote_write_access.arn
#   ]
#   oidc_fully_qualified_subjects = ["system:serviceaccount:opentelemetry-operator-system:adot-col-prom-metrics"]
# }

# module "irsa-adot-col-otlp-ingest" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
#   version = "5.52.2"

#   create_role  = true
#   role_name    = "adot-col-otlp-ingest"
#   provider_url = module.eks.cluster_oidc_issuer_url

#   role_policy_arns = [
#     data.aws_iam_policy.xray_write_access.arn
#   ]
#   oidc_fully_qualified_subjects = ["system:serviceaccount:opentelemetry-operator-system:adot-col-otlp-ingest"]
# }

# module "irsa-adot-col-container-logs" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
#   version = "5.52.2"

#   create_role  = true
#   role_name    = "adot-col-container-logs"
#   provider_url = module.eks.cluster_oidc_issuer_url

#   role_policy_arns = [
#     data.aws_iam_policy.cloudwatch_agent_server.arn
#   ]
#   oidc_fully_qualified_subjects = ["system:serviceaccount:opentelemetry-operator-system:adot-col-container-logs"]
# }

# module "adot_pod_identity" {
#   source  = "terraform-aws-modules/eks-pod-identity/aws"
#   version = "1.4.0"

#   name = "adot-collector-pod-identity"

#   # attach_custom_policy = true
#   additional_policy_arns = {
#     CloudWatchAgentServerPolicy       = data.aws_iam_policy.cloudwatch_agent_server.arn,
#     AmazonPrometheusRemoteWriteAccess = data.aws_iam_policy.amp_remote_write_access.arn,
#     AWSXrayWriteOnlyAccess            = data.aws_iam_policy.xray_write_access.arn
#   }

#   associations = {
#     main = {
#       cluster_name    = module.eks.cluster_name
#       namespace       = "monitoring"
#       service_account = "adot-collector"
#     }
#   }
# }

# data "aws_eks_addon_version" "adot" {
#   addon_name         = "adot"
#   kubernetes_version = var.kubernetes_version
#   most_recent        = true
# }

# resource "aws_eks_addon" "adot" {
#   cluster_name             = module.eks.cluster_name
#   addon_name               = "adot"
#   addon_version            = data.aws_eks_addon_version.adot.version
#   service_account_role_arn = module.irsa-adot-collector.iam_role_arn
#   # i.e., 'preserve' the custom value
#   resolve_conflicts_on_update = "OVERWRITE"
#   configuration_values = jsonencode({
#     manager = {
#       env = {
#       }
#     },
#     collector = {
#       prometheusMetrics = {
#         resources = {
#           limits = {
#             cpu    = "1000m",
#             memory = "750Mi"
#           },
#           requests = {
#             cpu    = "300m",
#             memory = "512Mi"
#           }
#         },
#         serviceAccount = {
#           annotations = {
#             "eks.amazonaws.com/role-arn" = module.irsa-adot-col-prom-metrics.iam_role_arn
#           }
#         },
#         pipelines = {
#           metrics = {
#             amp = {
#               enabled = true
#             },
#             emf = {
#               enabled = true
#             }
#           }
#         },
#         exporters = {
#           prometheusremotewrite = {
#             endpoint = "${aws_prometheus_workspace.cloudpipe.prometheus_endpoint}api/v1/remote_write"
#           }
#         }
#       },
#       otlpIngest = {
#         resources = {
#           limits = {
#             cpu    = "1000m",
#             memory = "750Mi"
#           },
#           requests = {
#             cpu    = "300m",
#             memory = "512Mi"
#           }
#         },
#         serviceAccount = {
#           annotations = {
#             "eks.amazonaws.com/role-arn" = module.irsa-adot-col-otlp-ingest.iam_role_arn
#           }
#         },
#         pipelines = {
#           traces = {
#             xray = {
#               enabled = true
#             }
#           }
#         }
#       },
#       containerLogs = {
#         serviceAccount = {
#           annotations = {
#             "eks.amazonaws.com/role-arn" = module.irsa-adot-col-container-logs.iam_role_arn
#           }
#         },
#         pipelines = {
#           logs = {
#             cloudwatchLogs = {
#               enabled = true
#             }
#           }
#         }
#       }
#     }
#   })
# }
