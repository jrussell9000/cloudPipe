#################################################################################
# EKS/K8s Addons
#################################################################################

#---------------------------------------------------------------
# IRSA for VPC CNI
#---------------------------------------------------------------
# module "vpc_cni_irsa_role" {
#   source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
#   role_name = join("_", [var.cluster_name, "vpc-cni"])
#   attach_vpc_cni_policy = true
#   vpc_cni_enable_ipv4   = true

#   oidc_providers = {
#     main = {
#       provider_arn               = module.eks.oidc_provider_arn
#       namespace_service_accounts = ["default:my-app", "canary:my-app"]
#     }
#   }
# }

#---------------------------------------------------------------
# IRSA for Karpenter
#---------------------------------------------------------------
# module "karpenter_irsa_role" {
#   source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

#   role_name                          = "karpenter_controller"
#   attach_karpenter_controller_policy = true

#   karpenter_controller_cluster_name         = module.eks.cluster_name
#   karpenter_controller_node_iam_role_arns = [module.eks.eks_managed_node_groups["eksControl_gpu"].iam_role_arn]

#   attach_vpc_cni_policy = true
#   vpc_cni_enable_ipv4   = true

#   oidc_providers = {
#     main = {
#       provider_arn               = module.eks.oidc_provider_arn
#       namespace_service_accounts = ["default:my-app", "canary:my-app"]
#     }
#   }
# }

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
# module "ebs_csi_driver_irsa_role" {
#   source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
#   role_name_prefix      = format("%s-%s-", local.name, "ebs-csi-driver")
#   attach_ebs_csi_policy = true
#   oidc_providers = {
#     main = {
#       provider_arn               = module.eks.oidc_provider_arn
#       namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
#     }
#   }
# }

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

/*********************
* EKS Managed Addons *
**********************/
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
    vpc-cni = {
      before_compute = true
      most_recent    = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    kube-proxy = {
      preserve = true
    }
  }

  #---------------------------------------
  # Kubernetes Add-ons
  #---------------------------------------
  #---------------------------------------------------------------
  # CoreDNS Autoscaler helps to scale for large EKS Clusters
  #   Further tuning for CoreDNS is to leverage NodeLocal DNSCache -> https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
  #---------------------------------------------------------------
  enable_cluster_proportional_autoscaler = true
  cluster_proportional_autoscaler = {
    values = [templatefile("${path.module}/helm-values/coredns-autoscaler-values.yaml", {
      target = "deployment/coredns"
    })]
    description = "Cluster Proportional Autoscaler for CoreDNS Service"
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                           = true
  karpenter_enable_spot_termination          = true
  karpenter_enable_instance_profile_creation = true
  karpenter_node = {
    iam_role_use_name_prefix = false
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }
  karpenter = {
    chart_version       = "v0.34.0"
    namespace           = "karpenter"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------
  # Metrics Server
  #---------------------------------------
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
  #---------------------------------------
  # Argo Workflows & Argo Events
  #---------------------------------------
  # enable_argo_workflows = true
  # argo_workflows = {
  #   chart_version = "0.41.14 "
  #   name       = "argo-workflows"
  #   namespace  = "argo-workflows"
  #   repository = "https://argoproj.github.io/argo-helm"
  #   values     = [templatefile("${path.module}/helm-values/argo-workflows-values.yaml", {})]
  # }

  # enable_argo_events = true
  # argo_events = {
  #   name       = "argo-events"
  #   namespace  = "argo-events"
  #   repository = "https://argoproj.github.io/argo-helm"
  #   values     = [templatefile("${path.module}/helm-values/argo-events-values.yaml", {})]
  # }
}


# Resource: Helm Release 
resource "helm_release" "argo_workflow_release" {
  depends_on = [module.irsa_role_argowf_server,
  module.irsa_role_argowf_controller]
  name             = lower(local.name)
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-workflows"
  namespace        = "argo-workflows"
  create_namespace = true

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
  reset_values     = true
  replace          = true

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

  values = [file("${path.module}/yamls/gpu-operator/gpuoperator-batch-tolerations.yaml")]
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
