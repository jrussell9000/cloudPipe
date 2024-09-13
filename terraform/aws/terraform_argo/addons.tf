#################################################################################
# EKS/K8s Addons
#################################################################################

#---------------------------------------------------------------
# IRSA for S3
#---------------------------------------------------------------

resource "aws_iam_policy" "argo_s3_irsa_iam_policy" {
  name        = "argo_s3_irsa_iam_policy"
  description = "S3 access policy for IRSA role assigned to Argo Workflows Artifact Repository"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = "arn:aws:s3:::brc-abcd"
      }
    ]
  })
}

# Resource: Helm Release 
resource "helm_release" "argo_workflow_release" {
  depends_on = [module.argo_workflows_server_irsa_aws,
  module.argo_workflows_controller_irsa_aws]
  name             = lower(local.name)
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-workflows"
  namespace        = "argo-workflows"
  create_namespace = true
  cleanup_on_fail  = true

  values = [
    templatefile("${path.module}/helm-values/argo-workflows-config.tftpl",
      {
        controllerSAname = var.argowf_controller_serviceaccount
        serverSAname     = var.argowf_server_serviceaccount
        controllerIAMarn = module.argo_workflows_controller_irsa_aws.iam_role_arn
        serverIAMarn     = module.argo_workflows_server_irsa_aws.iam_role_arn
    })
  ]
}

# resource "helm_release" "cert-manager" {
#   name             = lower(local.name)
#   repository       = "https://charts.jetstack.io"
#   chart            = "cert-manager"
#   namespace        = "kube-system"
#   create_namespace = false
#   cleanup_on_fail  = true

#   values = [file("${path.module}/helm-values/cert-manager-values.yaml")]
# }



module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_metrics_server = true
  metrics_server = {
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    chart_version    = "1.8.2"
    name             = "aws-load-balancer-controller"
    namespace        = "aws-lb-ctrl"
    create_namespace = true
    set = [{
      name  = "enableServiceMutatorWebhook"
      value = "false"
    }]
  }
}

/************************************
* NVIDIA Device Plugin Installation *
*************************************/

# resource "helm_release" "nvdp" {
#   name = "nvidia-device-plugin"
#   repository = "https://nvidia.github.io/k8s-device-plugin"
#   chart = "nvdp/nvidia-device-plugin"
#   version = "0.16.1"
#   namespace = var.nvdp_namespace
#   create_namespace = true
#   atomic = true
#   cleanup_on_fail = true
#   set {
#     name = "gfd.enabled"
#     value = "true"
#   }
#   set {
#     name = "migStrategy"
#     value = "single"
#   }
#   set {
#     name = "runtimeClassName"
#     value = "nvidia"
#   }
#   values = [file("${path.module}/yamls/nvidia-device-plugin/nvdp_config.yml")]
# }


# helm install --wait --generate-name -n nvidia-gpu-operator --create-namespace nvidia/gpu-operator --set driver.enabled=false --set toolkit.enabled=false --set runtimeClassName=nvidia

/***********************************
* NVIDIA GPU Operator Installation *
************************************/
# Installing the NVIDIA GPU Operator 
# https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html
resource "helm_release" "gpu_operator" {
  name             = "gpu-operator"
  repository       = "https://helm.ngc.nvidia.com/nvidia"
  chart            = "gpu-operator"
  version          = var.gpu_operator_version
  namespace        = var.gpu_operator_namespace
  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true


  # Chart Customization Options: 
  # https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html#chart-customization-options
  # Note: Need to specify the driver version and update it as necessaryk get
  set {
    name  = "driver.enabled"
    value = "false"
  }

  set {
    name  = "toolkit.enabled"
    value = "false"
  }

  set {
    name  = "mig.strategy"
    value = "single"
  }

  set {
    name  = "migManager.enabled"
    value = "true"
  }

  set {
    name  = "operator.runtimeClass"
    value = "nvidia"
  }

  set {
    name  = "migManager.env[0].name"
    value = "WITH_REBOOT"
  }

  set {
    name  = "migManager.env[0].value"
    value = "true"
    type  = "string"
  }

  set {
    name  = "migManager.default"
    value = "all-1g.10gb"
  }

  values = [file("${path.module}/yamls/gpu-operator/gpuoperator-karpenter-tolerations.yaml")]
}

# resource "kubernetes_config_map_v1" "time-slicing-config" {
#   metadata {
#     name = "time-slicing-config"
#   }
#   data = {
#     "time-slicing-config" = "${file("${path.module}/yamls/gpu-operator/time-slicing-config-fine.yaml")}"
#   }
# }

/*********************************
* Fluent-Bit for AWS Batch Setup *
**********************************/

# resource "kubectl_manifest" "fluent-bit-namespace" {

#   yaml_body = "${file("${path.module}/yamls/fluent-bit/cloudwatch-namespace.yaml")}"

# }

# resource "kubectl_manifest" "fluent-bit-cluster-info" {

#   yaml_body = "${file("${path.module}/yamls/fluent-bit/fluent-bit-cluster-info.yaml")}"

# }

# resource "kubectl_manifest" "fluent-bit-config" {

#   yaml_body = "${file("${path.module}/yamls/fluent-bit/fluent-bit.yaml")}"

# }
