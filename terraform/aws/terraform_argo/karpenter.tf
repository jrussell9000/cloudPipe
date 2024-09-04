
resource "kubernetes_manifest" "karpenter_node_class" {
  manifest = yamldecode(<<-YAML
    apiVersion: karpenter.k8s.aws/v1beta1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiFamily: AL2023
      role: ${module.eks_blueprints_addons.karpenter.node_iam_role_arn}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
      YAML
  )

  depends_on = [
    module.eks_blueprints_addons.karpenter
  ]
}

resource "kubernetes_manifest" "karpenter_node_pool" {
  manifest = yamldecode(<<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          nodeClassRef:
            name: default
          requirements:
            - key: "karpenter.k8s.aws/instance-category"
              operator: In
              values: ["c", "m", "r"]
            - key: "karpenter.k8s.aws/instance-cpu"
              operator: In
              values: ["4", "8", "16", "32"]
            - key: "karpenter.k8s.aws/instance-hypervisor"
              operator: In
              values: ["nitro"]
            - key: "karpenter.k8s.aws/instance-generation"
              operator: Gt
              values: ["2"]
      limits:
        cpu: 1000
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 30s
    YAML
  )
  depends_on = [
    kubernetes_manifest.karpenter_node_class
  ]
}

# # Example deployment using the [pause image](https://www.ianlewis.org/en/almighty-pause-container)
# # and starts with zero replicas
# resource "kubernetes_manifest" "karpenter_example_deployment" {
#   manifest = yamldecode(<<-YAML
#     apiVersion: apps/v1
#     kind: Deployment
#     metadata:
#       name: inflate
#     spec:
#       replicas: 0
#       selector:
#         matchLabels:
#           app: inflate
#       template:
#         metadata:
#           labels:
#             app: inflate
#         spec:
#           terminationGracePeriodSeconds: 0
#           containers:
#             - name: inflate
#               image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
#               resources:
#                 requests:
#                   cpu: 1
#     YAML
#   )
#   depends_on = [
#     module.eks_blueprints_addons.karpenter
#   ]
# }
