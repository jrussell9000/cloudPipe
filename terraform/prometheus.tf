#---------------------------------------------------------------
# GP3 Encrypted Storage Class
#---------------------------------------------------------------

resource "kubernetes_annotations" "gp2_default" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force      = true
  depends_on = [module.eks]
}

resource "kubernetes_storage_class" "ebs_csi_encrypted_gp3_storage_class" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    fsType    = "xfs"
    encrypted = true
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.gp2_default]
}

resource "aws_prometheus_workspace" "fastproc" {
  alias = "fastproc-amp"
}

module "prometheus_irsa_role" {
  source                                           = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version                                          = "5.44.0"
  amazon_managed_service_prometheus_workspace_arns = [aws_prometheus_workspace.fastproc.arn]
  attach_amazon_managed_service_prometheus_policy  = true
  role_name                                        = "amazon-managed-prometheus-irsa"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["monitoring:amazon-managed-prometheus-irsa"]
    }
  }
  depends_on = [aws_prometheus_workspace.fastproc]
}

# If this has trouble installing, try kubectl get secrets -n monitoring, then delete all the monitoring secrets
resource "helm_release" "prometheus" {
  namespace        = "monitoring"
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  version          = "~> 25.27.0"
  create_namespace = true
  wait             = true

  values = [templatefile("${path.module}/helm-values/prometheus/karpenter-prometheus-values.tftpl", {
    karpenter_namespace = var.karpenter_namespace
    prometheusIRSAarn   = module.prometheus_irsa_role.iam_role_arn
    prometheusIRSAname  = module.prometheus_irsa_role.iam_role_name
    amp_prometheus_url  = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.fastproc.id}"
  })]
  depends_on = [module.prometheus_irsa_role]
}

# helm install --namespace monitoring prometheus prometheus-community/prometheus --values prometheus-values.yaml

# Grafana Username: kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-user}" | base64 --decode ; echo
# Grafana Password: kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
resource "helm_release" "grafana" {
  namespace  = "monitoring"
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "~> 8.5.1"

  values = [templatefile("${path.module}/helm-values/prometheus/karpenter-grafana-values.tftpl", {
  })]

  depends_on = [helm_release.prometheus]
}
