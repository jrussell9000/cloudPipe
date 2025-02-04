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

