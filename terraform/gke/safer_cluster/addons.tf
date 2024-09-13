provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# Resource: Helm Release 
resource "helm_release" "argo_workflow_release" {
  name             = "${lower(local.root_name)}-argo-workflows"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-workflows"
  namespace        = "argo-workflows"
  create_namespace = true

  values = [
    templatefile("${path.module}/helm-values/argo-workflows-config.tftpl",
      {
        controllerSAname = var.argowf_controller_serviceaccount
        serverSAname     = var.argowf_server_serviceaccount
    })
  ]
}
