#################################################################################
# EKS/K8s Addons
#################################################################################

locals {
  cluster_secretstore_name = "external-secrets-clusterstore"
  cluster_secretstore_sa   = "external-secrets-sa"
  # Argo Workflows db secrets must be in the same namespace as the controller
  # https://github.com/argoproj/argo-helm/blob/main/charts/argo-workflows/values.yaml#L187
}

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.4"
  role_name_prefix      = format("%s-%s-", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

#---------------------------------------------------------------
# EKS Blueprints Addons
#---------------------------------------------------------------
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_cert_manager = true

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    set = [
      {
        name  = "vpcId"
        value = module.vpc.vpc_id
      },
      {
        name  = "podDisruptionBudget.maxUnavailable"
        value = 1
      },
      {
        # Cert-manager, external-secrets kick back errors if not set to false
        name  = "enableServiceMutatorWebhook"
        value = "false"
      }
    ]
  }

  # EKS Blueprints Addons installs the helm release, creates the IRSA account, 
  # and attaches the policy but does not set up the secret store
  enable_external_secrets = true
  # Defining the SA so we can reference it later
  external_secrets = {
    service_account_name = local.cluster_secretstore_sa
  }

  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
      preserve                 = false
      configuration_values     = jsonencode({ defaultStorageClass = { enabled = true } })
    }
  }
}

resource "time_sleep" "blueprints_addons_sleep" {
  depends_on = [
    module.eks_blueprints_addons
  ]
  create_duration = "15s"
}

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

  #values = [file("${path.module}/yamls/gpu-operator/gpuoperator-karpenter-tolerations.yaml")]
}

