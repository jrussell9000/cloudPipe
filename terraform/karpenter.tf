# https://github.com/terraform-aws-modules/terraform-aws-eks/tree/v20.24.1/modules/karpenter
module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"
  #version = "~> 20.24"

  cluster_name = module.eks.cluster_name

  # See https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/#preventing-apiserver-request-throttling
  # namespace = var.karpenter_namespace

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = "${var.name}-karpenter-node-iam-role"
  create_pod_identity_association = true
  create_instance_profile         = true

  node_iam_role_additional_policies = {
    AmazonEKS_CNI_Policy                     = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    AmazonEKSWorkerNodePolicy                = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    AmazonEC2ContainerRegistryReadOnlyPolicy = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    AmazonSSMManagedInstanceCore             = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    CloudWatchAgentServerPolicy              = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    AmazonEFSCSIDriverPolicy                 = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
    AmazonEKSVPCResourceController           = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  }
}

# Install Karpenter and modify default configuration
# If this returns an access error (e.g., 403 forbidden) - helm registry logout public.ecr.aws && docker logout public.ecr.aws
resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "kube-system"
  create_namespace = true
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.6.2"
  wait             = false

  depends_on = [helm_release.prometheus_crds]
  # https://github.com/aws/karpenter-provider-aws/tree/main/charts/karpenter
  values = [
    <<-EOT
    replicas: 1
    nodeSelector:
      karpenter.sh/controller: 'true'
    tolerations:
    - key: karpenter.sh/controller
      operator: Exists
      effect: NoSchedule
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: eks.amazonaws.com/nodegroup
                  operator: In
                  values:
                    - karpenter
    extraVolumes:
    - name: aws-iam-token
      projected:
        defaultMode: 420
        sources:
        - serviceAccountToken:
            audience: sts.amazonaws.com
            expirationSeconds: 86400
            path: token
    controller:
      extraVolumeMounts:
      - name: aws-iam-token
        mountPath: /var/run/secrets/eks.amazonaws.com/serviceaccount
        readOnly: true
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
      eksControlPlane: true
    EOT
  ]

  # lifecycle {
  #   ignore_changes = [
  #     repository_password
  #   ]
  # }
}

# Adding EC2nodeclasses and nodepools
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

resource "kubectl_manifest" "al2023-gpu-nodeclass" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/al2023-gpu-nodeclass.yaml",
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

resource "kubectl_manifest" "al2023-intel-light-nodepool" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/al2023-intel-light-nodepool.yaml",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "al2023-intel-heavy-nodepool" {
  yaml_body = templatefile("${path.module}/helm-values/karpenter/al2023-intel-heavy-nodepool.yaml",
    {
      karpenter_node_iam_role_name = module.karpenter.node_iam_role_name
      eks_cluster_name             = module.eks.cluster_name
  })

  depends_on = [
    helm_release.karpenter
  ]
}
