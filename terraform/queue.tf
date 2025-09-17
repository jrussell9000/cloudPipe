
# https://raw.githubusercontent.com/awslabs/data-on-eks/f94cebb6424ddcac0918730296b068098505aaaa/schedulers/terraform/argo-workflow/spark-team.tf

#---------------------------------------------------------------
# Argo Events
#---------------------------------------------------------------

# Create the Argo Events namespace
resource "kubernetes_namespace_v1" "argo_events" {
  metadata {
    name = var.argo_events_namespace
  }
}

# Install Argo Events
resource "helm_release" "argo_events" {
  name       = "argo-events"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-events"
  namespace  = kubernetes_namespace_v1.argo_events.metadata[0].name
  # version          = "~>2.4.0"
  create_namespace = false
  wait             = true
  values = [
    <<-EOT
    webhook:
      # -- Enable admission webhook. Applies only for cluster-wide installation
      enabled: true
    EOT
  ]

  depends_on = [kubernetes_namespace_v1.argo_events]
}

# Permissions necessary to read/send to/from SQS
data "aws_iam_policy_document" "sqs_argo_events" {
  statement {
    sid       = "AllowReadingAndSendingSQSfromArgoEvents"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "sqs:ListQueues",
      "sqs:GetQueueUrl",
      "sqs:ListDeadLetterSourceQueues",
      "sqs:ListMessageMoveTasks",
      "sqs:ReceiveMessage",
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:ListQueueTags",
      "sqs:DeleteMessage"
    ]
  }
}

resource "aws_iam_policy" "sqs_argo_events" {
  description = "IAM policy for Argo Events"
  name_prefix = format("%s-%s-", local.name, "argo-events")
  path        = "/"
  policy      = data.aws_iam_policy_document.sqs_argo_events.json
}

# Create an IRSA for Argo Events
# module "irsa_argo_events" {
#   source         = "aws-ia/eks-blueprints-addon/aws"
#   create_release = false
#   create_policy  = false
#   create_role    = true
#   role_name      = "${local.name}-${var.argo_events_namespace}"
#   role_policies  = { policy_event = aws_iam_policy.sqs_argo_events.arn }

#   oidc_providers = {
#     this = {
#       provider_arn    = module.eks.oidc_provider_arn
#       namespace       = var.argo_events_namespace
#       service_account = var.argo_events_handler_sa
#     }
#   }

#   depends_on = [kubernetes_namespace_v1.argo_events,
#   aws_iam_policy.sqs_argo_events]
# }

module "irsa_argo_events" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~>6.0"
  name    = var.argo_events_handler_sa

  policies = {
    SQSArgoEventsPolicy = aws_iam_policy.sqs_argo_events.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.argo_events_namespace}:${var.argo_events_handler_sa}"]
    }
  }
}



# Create a service account for Argo Events and annotate it with the arn of the IRSA created above
resource "kubernetes_service_account_v1" "argo_events_handler_sa" {
  metadata {
    name        = var.argo_events_handler_sa
    namespace   = var.argo_events_namespace
    annotations = { "eks.amazonaws.com/role-arn" : module.irsa_argo_events.arn }
  }
  automount_service_account_token = true
  depends_on                      = [kubernetes_namespace_v1.argo_events]
}

# ???
resource "kubernetes_secret_v1" "event_sa" {
  metadata {
    name      = "${var.argo_events_handler_sa}-secret"
    namespace = var.argo_events_namespace
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.argo_events_handler_sa.metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.argo_events.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"

  depends_on = [kubernetes_namespace_v1.argo_events]
}

#---------------------------------------------------------------
# SQS
#---------------------------------------------------------------

# Creating a job queue for the workflow
resource "aws_sqs_queue" "job_queue" {
  name                        = "${var.name}-jobqueue.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}

# Install eventbus pods
resource "kubectl_manifest" "argo-events-eventbus" {
  yaml_body  = file("${path.module}/yamls/argo/events/eventbus.yaml")
  depends_on = [helm_release.argo_events]
}

# Install event source for AWS SQS
resource "kubectl_manifest" "argo-events-sqs-eventsource" {
  yaml_body = templatefile("${path.module}/yamls/argo/events/eventsource-sqs.yaml", {
    event_sa   = kubernetes_service_account_v1.argo_events_handler_sa.metadata[0].name
    queue_name = aws_sqs_queue.job_queue.name
    region     = local.region
    endpoint   = aws_sqs_queue.job_queue.url
  })
  depends_on = [helm_release.argo_events]
}

resource "kubernetes_cluster_role_v1" "argo-events-handler" {
  metadata {
    name = "argo-events-handler-cluster-role"
  }
  rule {
    api_groups = ["argoproj.io"]
    resources  = ["workflows", "workflowtemplates", "cronworkflows", "clusterworkflowtemplates"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding_v1" "argo-events-handler-argo-events" {
  metadata {
    name      = "argo-events-handler-role-binding-argo-events"
    namespace = "argo-events"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.argo-events-handler.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.argo_events_handler_sa.metadata[0].name
    namespace = "argo-events"
    api_group = ""
  }
}

resource "kubernetes_role_binding_v1" "argo-events-handler-argo-workflows" {
  metadata {
    name      = "argo-events-handler-role-binding-argo-workflows"
    namespace = "argo-workflows"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.argo-events-handler.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.argo_events_handler_sa.metadata[0].name
    namespace = "argo-events"
    api_group = ""
  }
}

# Create an Argo Event Sensor to trigger workflows
# Need to use templatefile here because the values are hardcoded
resource "kubectl_manifest" "argo-events-sensor" {
  yaml_body = templatefile("${path.module}/yamls/argo/events/cloudpipe-trigger.yaml",
    {
      argoworkflows_ns = var.argo_workflows_namespace
      workflow2trigger = var.argo_workflows_workflow2trigger
  })
  depends_on = [kubernetes_cluster_role_v1.argo-events-handler,
    kubernetes_role_binding_v1.argo-events-handler-argo-events,
  kubernetes_role_binding_v1.argo-events-handler-argo-workflows]
}

