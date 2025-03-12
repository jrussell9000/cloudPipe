# https://github.com/terraform-aws-modules/terraform-aws-eks/tree/v20.24.1/modules/karpenter
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24"

  cluster_name = module.eks.cluster_name
  # Enable permissions in the 'new' v1.0 releases of Karpenter (defaults to false as of 021925 )
  enable_v1_permissions = true
  namespace             = var.karpenter_namespace

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = "${var.name}-karpenter-node-iam-role"
  create_pod_identity_association = true

  node_iam_role_additional_policies = {
    AmazonEKS_CNI_Policy                     = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    AmazonEKSWorkerNodePolicy                = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    AmazonEC2ContainerRegistryReadOnlyPolicy = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    AmazonSSMManagedInstanceCore             = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    CloudWatchAgentServerPolicy              = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }
}

# If this returns an access error (e.g., 403 forbidden) - helm registry logout public.ecr.aws && docker logout public.ecr.aws
resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = var.karpenter_namespace
  create_namespace = true
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "~> 1.0"
  wait             = false

  values = [
    <<-EOT
    nodeSelector:
      karpenter.sh/controller: 'true'
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - key: karpenter.sh/controller
        operator: Exists
        effect: NoSchedule
    webhook:
      enabled: false
    EOT
  ]
}


resource "kubectl_manifest" "al2023-nodeclass" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/al2023-nodeclass.yaml",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "al2023-gpu-nodepool" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/al2023-gpu-nodepool.yaml",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "al2023-cpulight-nodepool" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/al2023-cpulight-nodepool.yaml",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "al2023-cpuheavy-nodepool" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/al2023-cpuheavy-nodepool.yaml",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}
