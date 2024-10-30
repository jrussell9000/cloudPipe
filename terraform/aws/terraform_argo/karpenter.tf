# https://github.com/terraform-aws-modules/terraform-aws-eks/tree/v20.24.1/modules/karpenter
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.11"

  cluster_name = module.eks.cluster_name

  create_pod_identity_association = true

  # Enable permissions in the 'new' v1.0 releases of Karpenter
  enable_v1_permissions = true
  namespace             = var.karpenter_namespace

  create_node_iam_role          = true
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.cluster_name}-node-iam-role"
  node_iam_role_additional_policies = {
    AmazonEKS_CNI_Policy                     = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    AmazonEKSWorkerNodePolicy                = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    AmazonEC2ContainerRegistryReadOnlyPolicy = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    AmazonSSMManagedInstanceCore             = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

# Karpenter monitoring requires the Prometheus Operator CRDs
resource "helm_release" "prometheus_operator_crds" {
  namespace        = "monitoring"
  name             = "prometheus-operator-crds"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus-operator-crds"
  version          = "~> 14.0.0"
  create_namespace = true
  wait             = true
}

# If this returns an access error (e.g., 403 forbidden) - helm registry logout public.ecr.aws
resource "helm_release" "karpenter" {
  namespace  = var.karpenter_namespace
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  #version          = "1.0.2"
  wait             = true
  create_namespace = true

  values = [
    <<-EOT
    nodeSelector:
      karpenter.sh/controller: 'true'
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - key: karpenter.sh/controller
        operator: Exists
        effect: NoSchedule
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    # serviceMonitor:
      # enabled: true
    EOT
  ]
  # use of serviceMonitor requires that CRDs from Prometheus Operator are already installed
  depends_on = [module.karpenter]
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

resource "kubectl_manifest" "al2-gpu-nodepool" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/al2-gpu-nodepool.tftpl",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "al2-gpu-nodeclass" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/al2-gpu-nodeclass.tftpl",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "al2-cpuheavy-nodepool" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/al2-cpuheavy-nodepool.tftpl",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "al2-cpuheavy-nodeclass" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/al2-cpuheavy-nodeclass.tftpl",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}
