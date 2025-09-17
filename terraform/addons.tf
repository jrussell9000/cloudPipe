#################################################################################
# EKS/K8s Addons
#################################################################################

resource "kubernetes_storage_class" "ebs_csi_encrypted_gp3_storage_class" {
  metadata {
    name = "ebs-sc"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "Immediate"
  parameters = {
    fsType    = "xfs"
    encrypted = true
    type      = "gp3"
  }

  depends_on = [helm_release.aws_ebs_csi_driver]
}


# #---------------------------------------------------------------
# # EKS Blueprints Addons
# #---------------------------------------------------------------
# module "eks_blueprints_addons" {
#   source  = "aws-ia/eks-blueprints-addons/aws"
#   version = "~> 1.0"

#   cluster_name      = module.eks.cluster_name
#   cluster_endpoint  = module.eks.cluster_endpoint
#   cluster_version   = module.eks.cluster_version
#   oidc_provider_arn = module.eks.oidc_provider_arn

#   # CoreDNS Autoscaler helps to scale for large EKS Clusters
#   # Further tuning for CoreDNS is to leverage NodeLocal DNSCache -> https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
#   #---------------------------------------------------------------
#   enable_cluster_proportional_autoscaler = true
#   cluster_proportional_autoscaler = {
#     values = [templatefile("${path.module}/helm-values/coredns-autoscaler-values.yaml", {
#       target = "deployment/coredns"
#     })]
#     description = "Cluster Proportional Autoscaler for CoreDNS Service"
#   }
# }


module "external_secrets_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~>6.0"

  name                                               = "external-secrets-irsa-role"
  attach_external_secrets_policy                     = true
  external_secrets_secrets_manager_create_permission = true
  external_secrets_ssm_parameter_arns                = ["arn:aws:ssm:*:*:parameter/*"]
  external_secrets_secrets_manager_arns              = ["arn:aws:secretsmanager:*:*:secret:*"]
  external_secrets_kms_key_arns                      = ["arn:aws:kms:*:*:key/*"]
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets-sa"]
    }
  }
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  cleanup_on_fail  = true
  recreate_pods    = true

  values = [
    <<-EOT
    serviceAccount:
      name: "external-secrets-sa"
      annotations:
          eks.amazonaws.com/role-arn: "${module.external_secrets_irsa_role.arn}"
    EOT
  ]
}

module "aws_ebs_csi_pod_identity" {
  source                    = "terraform-aws-modules/eks-pod-identity/aws"
  name                      = "aws-ebs-csi-pod-identity"
  attach_aws_ebs_csi_policy = true
  aws_ebs_csi_kms_arns      = ["arn:aws:kms:*:*:key/*"]
  associations = {
    cloudpipe = {
      cluster_name    = "${var.name}"
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }
}

resource "helm_release" "aws_ebs_csi_driver" {
  name             = "aws-ebs-csi-driver"
  repository       = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart            = "aws-ebs-csi-driver"
  namespace        = "kube-system"
  create_namespace = false
  cleanup_on_fail  = true
  recreate_pods    = true
}

module "aws_efs_csi_pod_identity" {
  source                    = "terraform-aws-modules/eks-pod-identity/aws"
  name                      = "aws-efs-csi"
  attach_aws_efs_csi_policy = true

  associations = {
    cloudpipe = {
      cluster_name    = "${module.eks.cluster_name}"
      namespace       = "kube-system"
      service_account = "efs-csi-controller-sa"
    }
  }
}

resource "helm_release" "aws_efs_csi_driver" {
  name             = "aws-efs-csi-driver"
  repository       = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
  chart            = "aws-efs-csi-driver"
  namespace        = "kube-system"
  create_namespace = false
  cleanup_on_fail  = true

  # https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/charts/aws-efs-csi-driver/values.yaml
  values = [
    <<-EOT
    controller:
      # Delete the path on EFS when deleting an access point
      deleteAccessPointRootDir: true
      # see: https://github.com/kubernetes-sigs/aws-efs-csi-driver?tab=readme-ov-file#timeouts
      timeout: 60s
    tolerations:
      - key: "CriticalAddonsOnly"
        value: "true"
        effect: "NoSchedule"
    node:
      volMetricsOptIn: true
    EOT
  ]
}


data "aws_route53_zone" "brc" {
  name = "braveresearchcollaborative.org"
}

module "cert_manager_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "cert-manager"

  attach_cert_manager_policy    = true
  cert_manager_hosted_zone_arns = [data.aws_route53_zone.brc.arn]

  # Pod Identity Associations
  associations = {
    cloudpipe = {
      cluster_name = "${module.eks.cluster_name}"
      # These are the default namespace and SA in cert-manager
      namespace       = "cert-manager"
      service_account = "cert-manager"
    }
  }
  depends_on = [helm_release.cert-manager]
}

resource "helm_release" "cert-manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  cleanup_on_fail  = true

  values = [
    <<-EOT
    crds:
      enabled: true
    extraEnv:
      - name: AWS_REGION
        value: ${var.region}
    EOT
  ]
}


# resource "helm_release" "awspca" {
#   name       = "aws-privateca-issuer"
#   repository = "https://cert-manager.github.io/aws-privateca-issuer"
#   chart      = "aws-privateca-issuer"
#   version    = "~>1.0"
# }

# data "aws_iam_policy_document" "assume_role" {
#   statement {
#     effect = "Allow"

#     principals {
#       type        = "Service"
#       identifiers = ["pods.eks.amazonaws.com"]
#     }

#     actions = [
#       "sts:AssumeRole",
#       "sts:TagSession"
#     ]
#   }
# }

# resource "aws_iam_role" "kube-image-keeper" {
#   name               = "kube-image-keeper-registry-role"
#   assume_role_policy = data.aws_iam_policy_document.assume_role.json
# }

# resource "aws_iam_role_policy_attachment" "ecr_access" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonElasticContainerRegistryPublicFullAccess"
#   role       = aws_iam_role.kube-image-keeper.name
# }

# resource "aws_iam_role_policy_attachment" "efs_access" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientFullAccess"
#   role       = aws_iam_role.kube-image-keeper.name
# }

# resource "helm_release" "kube-image-keeper" {
#   name             = "kube-image-keeper"
#   repository       = "https://charts.enix.io"
#   chart            = "kube-image-keeper"
#   namespace        = "kuik-system"
#   create_namespace = true

#   values = [
#     <<-EOT
#     registry:
#       persistence:
#         enabled: true
#         accessModes: 'ReadWriteMany'
#         storageClass: nfs
#         size: 100Gi
#     controllers:
#       webhook:
#         ignoredImages:
#           - .*cloudwatch.*
#         ignoredNamespaces:
#           - amazon-cloudwatch
#     EOT
#   ]
# }

# resource "aws_eks_pod_identity_association" "kube-image-keeper-registry" {
#   cluster_name    = module.eks.cluster_name
#   namespace       = "kuik-system"
#   service_account = "kube-image-keeper-registry"
#   role_arn        = aws_iam_role.kube-image-keeper.arn

#   depends_on = [helm_release.kube-image-keeper]
# }

# resource "aws_eks_pod_identity_association" "kube-image-keeper-controllers" {
#   cluster_name    = module.eks.cluster_name
#   namespace       = "kuik-system"
#   service_account = "kube-image-keeper-controllers"
#   role_arn        = aws_iam_role.kube-image-keeper.arn

#   depends_on = [helm_release.kube-image-keeper]
# }


# /***********************************
# * NVIDIA GPU Operator Installation *
# ************************************/
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

  values = [
    <<-EOT
    tolerations:
      - key: "CriticalAddonsOnly"
        value: "true"
        effect: "NoSchedule"
    EOT
  ]
  # Chart Customization Options:
  # https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html#chart-customization-options
  set = [
    {
      # The AL2023_x86_64_NVIDIA AMI comes prepackaged with NVIDIA drivers
      name  = "driver.enabled"
      value = "false"
    },
    {
      name  = "toolkit.enabled"
      value = "false"
    },
    {
      name  = "mig.strategy"
      value = "single"
    },
    {
      name  = "migManager.enabled"
      value = "true"
    },
    {
      name  = "operator.runtimeClass"
      value = "nvidia"
    },
    {
      name  = "migManager.env[0].name"
      value = "WITH_REBOOT"
    },
    {
      name  = "migManager.env[0].value"
      value = "true"
      type  = "string"
    },
    {
      name  = "migManager.default"
      value = "all-1g.10gb"
    }
  ]
}
