
# https://raw.githubusercontent.com/awslabs/data-on-eks/f94cebb6424ddcac0918730296b068098505aaaa/schedulers/terraform/argo-workflow/spark-team.tf

# Move these to variables
locals {
  event_namespace       = "argo-events"
  event_service_account = "event-sa"
}

resource "helm_release" "argo_events" {
  name             = "argo-events"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-events"
  namespace        = "argo-events"
  version          = "~>2.4.0"
  create_namespace = true
  values = [
    file("${path.module}/helm-values/argo/events/argo-events-values.yaml")
  ]
}

#---------------------------------------------------------------
# IRSA for Argo events to read and send SQS
#---------------------------------------------------------------

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

resource "kubernetes_service_account_v1" "event_sa" {
  metadata {
    name        = local.event_service_account
    namespace   = local.event_namespace
    annotations = { "eks.amazonaws.com/role-arn" : module.irsa_argo_events.iam_role_arn }
  }
  automount_service_account_token = true
  depends_on                      = [helm_release.argo_events]
}

resource "kubernetes_secret_v1" "event_sa" {
  metadata {
    name      = "${local.event_service_account}-secret"
    namespace = local.event_namespace
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.event_sa.metadata[0].name
      "kubernetes.io/service-account.namespace" = local.event_namespace
    }
  }
  type = "kubernetes.io/service-account-token"

  depends_on = [helm_release.argo_events]
}

module "irsa_argo_events" {
  source         = "aws-ia/eks-blueprints-addon/aws"
  version        = "~> 1.0"
  create_release = false
  create_policy  = false
  create_role    = true
  role_name      = "${local.name}-${local.event_namespace}"
  role_policies  = { policy_event = aws_iam_policy.sqs_argo_events.arn }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = local.event_namespace
      service_account = local.event_service_account
    }
  }

  depends_on = [module.eks_blueprints_addons,
  helm_release.argo_events]
}


resource "aws_sqs_queue" "job_queue" {
  name                        = "${var.name}-jobqueue.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}



# These don't load consistently...need to find a better alternative to kubectl_manifest

# Install eventbus pods
resource "kubectl_manifest" "argo-events-eventbus" {
  yaml_body = file("${path.module}/yamls/argo/events/eventbus.yaml")
}

# Install event source for AWS SQS
# Templatefile wasn't working here so these values are temporarily hardcoded
resource "kubectl_manifest" "argo-events-sqs-eventsource" {
  yaml_body = templatefile("${path.module}/yamls/argo/events/eventsource-sqs.yaml", {
    queue_name = aws_sqs_queue.job_queue.name
    region     = local.region
  })
}

# Create an RBAC service account for the sensor
resource "kubectl_manifest" "argo-events-sensor-rbac" {
  yaml_body = file("${path.module}/yamls/argo/events/sensor-rbac.yaml")
}

# Create an Argo Event Sensor to trigger workflows
# Need to use templatefile here because the values are hardcoded
resource "kubectl_manifest" "argo-events-sensor" {
  yaml_body = file("${path.module}/yamls/argo/events/cloudpipe-trigger.yaml")
}

