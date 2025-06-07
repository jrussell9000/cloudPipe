# see: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/install-CloudWatch-Observability-EKS-addon.html
resource "aws_prometheus_workspace" "cloudpipe" {
  alias = "${var.name}-prometheus"
}



resource "helm_release" "amazon_cloudwatch_observability" {
  name             = "amazon-cloudwatch"
  repository       = "https://aws-observability.github.io/helm-charts"
  chart            = "amazon-cloudwatch-observability"
  namespace        = "amazon-cloudwatch"
  create_namespace = true
  wait             = true

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "agent.defaultConfig.metrics.metrics_destinations.amp.workspace_id"
    value = aws_prometheus_workspace.cloudpipe.id
  }
  set {
    name  = "serviceAccount.name"
    value = "cloudwatch-agent"
  }
}


module "aws_cloudwatch_observability_pod_identity" {
  source                                     = "terraform-aws-modules/eks-pod-identity/aws"
  name                                       = "aws-cloudwatch-observability"
  attach_aws_cloudwatch_observability_policy = true

  associations = {
    cluster1 = {
      namespace       = "amazon-cloudwatch"
      service_account = "cloudwatch-agent"
      cluster_name    = module.eks.cluster_name
    }
  }
  depends_on = [helm_release.amazon_cloudwatch_observability]
}

# resource "aws_eks_addon" "amazon-cloudwatch-observability" {
#   cluster_name = module.eks.cluster_name
#   addon_name   = "amazon-cloudwatch-observability"
#   pod_identity_association {
#     role_arn        = module.aws_cloudwatch_observability_pod_identity.iam_role_arn
#     service_account = "cloudwatch-agent"
#   }
#   configuration_values = file("${path.module}/helm-values/amazon-cloudwatch-observability/amazon-cloudwatch-observability-values.json")
# }
