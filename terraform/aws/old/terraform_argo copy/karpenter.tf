
# https://github.com/terraform-aws-modules/terraform-aws-eks/tree/v20.24.1/modules/karpenter
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24"

  cluster_name = module.eks.cluster_name

  enable_pod_identity             = true
  create_pod_identity_association = true

  # enable_v1_permissions = true

  # If we're using the node IAM role created by EKS, we don't need to create one
  # and we don't need to give it an access entry
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.cluster_name}-node-iam-role"
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    ArgoS3AccessPolicy           = aws_iam_policy.argo_workflow_s3.arn
  }
}


# If this returns an access error (e.g., 403 forbidden) - helm registry logout public.ecr.aws
resource "helm_release" "karpenter" {
  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  # repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  # repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart   = "karpenter"
  version = "1.0.2"
  wait    = false
  # atomic          = true
  # cleanup_on_fail = true

  values = [
    <<-EOT
    serviceAccount:
      # Karpenter pod identity service account
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]
}

# Terraform loops would be a cleaner way to code this, but this works for now:
# see: https://github.com/SPHTech-Platform/terraform-aws-eks/blob/b5dab528d8c0b7120ac6a418966e93b7185be1eb/modules/karpenter/karpenter.tf


resource "kubectl_manifest" "light-use-nodepool" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/light-use-nodepool.tftpl",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "light-use-nodeclass" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/light-use-nodeclass.tftpl",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "fs-segmentation-nodepool" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/fs-segmentation-nodepool.tftpl",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "fs-segmentation-nodeclass" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/fs-segmentation-nodeclass.tftpl",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "fs-parcellation-nodepool" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/fs-parcellation-nodepool.tftpl",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "fs-parcellation-nodeclass" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/fs-parcellation-nodeclass.tftpl",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}

