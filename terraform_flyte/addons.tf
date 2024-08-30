#################################################################################
# EKS/K8s Addons
#################################################################################

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.20"
  role_name_prefix      = format("%s-%s-", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
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

  # We want to wait for the Fargate profiles to be deployed first
  create_delay_dependencies = [for prof in module.eks.fargate_profiles : prof.fargate_profile_arn]

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      preserve = true
    }
    vpc-cni = {
      before_compute = true
      preserve = true
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
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter_node = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }
  karpenter = {
    chart_version       = "v0.34.0"
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
    chart_version = "1.8.2"
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
    name = "toolkit.enabled"
    value = "false"
  }

  set {
    name = "mig.strategy"
    value = "single"
  }

  set {
    name = "migManager.enabled"
    value = "true"
  }

  set {
    name = "operator.runtimeClass"
    value = "nvidia"
  }

  set {
    name = "migManager.env[0].name"
    value = "WITH_REBOOT"
  }

  set {
    name = "migManager.env[0].value"
    value = "true"
    type = "string"
  }

  set {
    name = "migManager.default"
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