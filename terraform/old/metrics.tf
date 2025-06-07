resource "aws_security_group" "otel" {
  name        = "${var.name}-opentelemetry-sg"
  vpc_id      = module.vpc.vpc_id
  description = "Security group allowing ingress/egress rules required for OTEL"
}

resource "aws_vpc_security_group_ingress_rule" "otel_healthzport" {
  security_group_id = aws_security_group.otel.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8081
}

resource "aws_vpc_security_group_ingress_rule" "otel_webhookport" {
  security_group_id = aws_security_group.otel.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 9443
  ip_protocol       = "tcp"
  to_port           = 9443
}

resource "aws_vpc_security_group_ingress_rule" "otel_metricsport" {
  security_group_id = aws_security_group.otel.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 8081
  ip_protocol       = "tcp"
  to_port           = 8081
}

resource "aws_vpc_security_group_ingress_rule" "otel_admissionwebhook" {
  security_group_id = aws_security_group.otel.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "kubernetes_namespace_v1" "adot" {
  metadata {
    # If using EKS addon, namespace must be "opentelemetry-operator-system"
    name = "opentelemetry-operator-system"
  }
}

resource "kubernetes_role_v1" "adot" {

  metadata {
    name      = "adot"
    namespace = kubernetes_namespace_v1.adot.metadata[0].name
  }

  rule {
    api_groups     = [""]
    resources      = ["serviceaccounts"]
    resource_names = ["opentelemetry-operator-controller-manager"]
    verbs          = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups     = ["rbac.authorization.k8s.io"]
    resources      = ["roles"]
    resource_names = ["opentelemetry-operator-leader-election-role"]
    verbs          = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups     = ["rbac.authorization.k8s.io"]
    resources      = ["rolebindings"]
    resource_names = ["opentelemetry-operator-leader-election-rolebinding"]
    verbs          = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups     = [""]
    resources      = ["services"]
    resource_names = ["opentelemetry-operator-controller-manager-metrics-service", "opentelemetry-operator-webhook-service"]
    verbs          = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups     = ["apps"]
    resources      = ["deployments"]
    resource_names = ["opentelemetry-operator-controller-manager"]
    verbs          = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups     = ["cert-manager.io"]
    resources      = ["certificates", "issuers"]
    resource_names = ["opentelemetry-operator-serving-cert", "opentelemetry-operator-selfsigned-issuer"]
    verbs          = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps/status"]
    verbs      = ["get", "update", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["list"]
  }
}

resource "kubernetes_role_binding_v1" "adot" {

  metadata {
    name      = "eks:addon-manager"
    namespace = kubernetes_namespace_v1.adot.metadata[0].name
  }

  subject {
    kind      = "User"
    name      = "eks:addon-manager"
    api_group = "rbac.authorization.k8s.io"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "eks:addon-manager"
  }
}

resource "kubernetes_cluster_role_v1" "adot" {

  metadata {
    name = "eks:addon-manager-otel"
  }

  rule {
    api_groups     = ["apiextensions.k8s.io"]
    resources      = ["customresourcedefinitions"]
    resource_names = ["opentelemetrycollectors.opentelemetry.io", "instrumentations.opentelemetry.io"]
    verbs          = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups     = [""]
    resources      = ["namespaces"]
    resource_names = [kubernetes_namespace_v1.adot.metadata[0].name]
    verbs          = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups     = ["rbac.authorization.k8s.io"]
    resources      = ["clusterroles"]
    resource_names = ["opentelemetry-operator-manager-role", "opentelemetry-operator-metrics-reader", "opentelemetry-operator-proxy-role"]
    verbs          = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups     = ["rbac.authorization.k8s.io"]
    resources      = ["clusterrolebindings"]
    resource_names = ["opentelemetry-operator-manager-rolebinding", "opentelemetry-operator-proxy-rolebinding"]
    verbs          = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups     = ["admissionregistration.k8s.io"]
    resources      = ["mutatingwebhookconfigurations", "validatingwebhookconfigurations"]
    resource_names = ["opentelemetry-operator-mutating-webhook-configuration", "opentelemetry-operator-validating-webhook-configuration"]
    verbs          = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    non_resource_urls = ["/metrics"]
    verbs             = ["get"]
  }
  rule {
    api_groups = ["metrics.eks.amazonaws.com"]
    verbs      = ["get"]
    resources  = ["kcm/metrics", "ksh/metrics"]
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["serviceaccounts"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["daemonsets"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["replicasets"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["statefulsets"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["create", "get", "list", "update"]
  }
  rule {
    api_groups = ["opentelemetry.io"]
    resources  = ["opentelemetrycollectors"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["opentelemetry.io"]
    resources  = ["opentelemetrycollectors/finalizers"]
    verbs      = ["get", "patch", "update"]
  }
  rule {
    api_groups = ["opentelemetry.io"]
    resources  = ["opentelemetrycollectors/status"]
    verbs      = ["get", "patch", "update"]
  }
  rule {
    api_groups = ["opentelemetry.io"]
    resources  = ["instrumentations"]
    verbs      = ["get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["authentication.k8s.io"]
    resources  = ["tokenreviews"]
    verbs      = ["create"]
  }
  rule {
    api_groups = ["authorization.k8s.io"]
    resources  = ["subjectaccessreviews"]
    verbs      = ["create"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "adot" {
  metadata {
    name = "eks:addon-manager-otel"
  }
  subject {
    kind      = "User"
    name      = "eks:addon-manager"
    api_group = "rbac.authorization.k8s.io"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "eks:addon-manager-otel"
  }
}

module "iam_assumable_role_adot_amp" {
  source       = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version      = "~> v5.5.0"
  create_role  = true
  role_name    = "${var.name}-adot-col-prom-metrics"
  provider_url = module.eks.cluster_oidc_issuer_url
  role_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonPrometheusRemoteWriteAccess",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
  oidc_fully_qualified_subjects = ["system:serviceaccount:${kubernetes_namespace_v1.adot.metadata[0].name}:adot-col-prom-metrics"]
}

module "iam_assumable_role_adot_otlp_ingest" {
  source       = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version      = "~> v5.5.0"
  create_role  = true
  role_name    = "${var.name}-adot-col-otlp-ingest"
  provider_url = module.eks.cluster_oidc_issuer_url
  role_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXrayWriteOnlyAccess"
  ]
  oidc_fully_qualified_subjects = ["system:serviceaccount:${kubernetes_namespace_v1.adot.metadata[0].name}:adot-col-otlp-ingest"]
}

# ADOT Container Logging functionality isn't ready for prime time as of 03/2025
# module "iam_assumable_role_adot_container_logs" {
#   source       = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
#   version      = "~> v5.5.0"
#   create_role  = true
#   role_name    = "${var.name}-adot-col-container-logs"
#   provider_url = module.eks.cluster_oidc_issuer_url
#   role_policy_arns = [
#     "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
#   ]
#   oidc_fully_qualified_subjects = ["system:serviceaccount:${kubernetes_namespace_v1.adot.metadata[0].name}:adot-col-container-logs"]
# }

resource "aws_prometheus_workspace" "cloudpipe" {
  alias = "${var.name}-prometheus"
}

resource "helm_release" "opentelemetry_operator" {

  depends_on = [
    module.cert_manager
  ]

  name             = "opentelemetry-operator"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-operator"
  namespace        = kubernetes_namespace_v1.adot.metadata[0].name
  create_namespace = false
  version          = var.operator_chart_version
  wait             = false

  values = [
    file("${path.module}/helm-values/opentelemetry/opentelemetryoperator.yaml")
  ]
}

# resource "helm_release" "opentelemetry_collector" {

#   depends_on = [helm_release.opentelemetry_operator]

#   name             = "opentelemetry-collector"
#   repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
#   chart            = "opentelemetry-collector"
#   namespace        = kubernetes_namespace_v1.adot.metadata[0].name
#   create_namespace = false
#   version          = "0.120.2"
#   wait             = false

# }

resource "kubectl_manifest" "otel_collector" {
  depends_on = [helm_release.opentelemetry_operator]
  yaml_body  = <<YAML
    apiVersion: opentelemetry.io/v1beta1
    kind: OpenTelemetryCollector
    metadata:
      name: cloudpipe-collector
      namespace: ${kubernetes_namespace_v1.adot.metadata[0].name}
    spec:
      mode: deployment
      presets:
        kubernetesAttributes:
          enabled: true
          # You can also configure the preset to add all of the associated pod's labels and annotations to you telemetry.
          # The label/annotation name will become the resource attribute's key.
          extractAllPodLabels: true
          extractAllPodAnnotations: true
        kubeletMetrics:
          enabled: true
        hostMetrics:
          enabled: true
        kubernetesEvents:
          enabled: true
      hostNetwork: true
      config:
        receivers:
          prometheus:
            config:
              global:
                scrape_interval: 15s
                scrape_timeout: 10s

              scrape_configs:

              - job_name: kubernetes-nodes-cadvisor
                bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
                kubernetes_sd_configs:
                - role: node
                relabel_configs:
                - action: labelmap
                  regex: __meta_kubernetes_node_label_(.+)
                - replacement: kubernetes.default.svc:443
                  target_label: __address__
                - regex: (.+)
                  replacement: /api/v1/nodes/$$1/proxy/metrics/cadvisor
                  source_labels:
                  - __meta_kubernetes_node_name
                  target_label: __metrics_path__
                scheme: https
                tls_config:
                  ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
                  insecure_skip_verify: true
        processors:
          batch/metrics:
            timeout: 60s

        exporters:
          prometheusremotewrite:
            # replace this with your endpoint
            endpoint: ${aws_prometheus_workspace.cloudpipe.prometheus_endpoint}
            auth:
              authenticator: sigv4auth

        service:
          extensions: [sigv4auth]
          pipelines:
            metrics:
              receivers: [prometheus]
              processors: [batch/metrics]
              exporters: [prometheusremotewrite]

  YAML
}

locals {
  collector_configuration = <<EOF
{
  "collector": {
    "prometheusMetrics": {
      "serviceAccount": {
        "annotations": {
          "eks.amazonaws.com/role-arn": "${module.iam_assumable_role_adot_amp.iam_role_arn}"
        }
      },
      "pipelines": {
        "metrics": {
          "amp": {
            "enabled": true
          },
          "emf": {
            "enabled": true
          }
        }
      },
      "exporters": {
        "prometheusremotewrite": {
          "endpoint": "${aws_prometheus_workspace.cloudpipe.prometheus_endpoint}api/v1/remote_write"
        }
      }
    },
    "otlpIngest": {
      "serviceAccount": {
        "annotations": {
          "eks.amazonaws.com/role-arn": "${module.iam_assumable_role_adot_otlp_ingest.iam_role_arn}"
        }
      },
      "pipelines": {
        "traces": {
          "xray": {
            "enabled": true
          }
        }
      }
    },
  }
}
EOF
}

# ADOT Container Logging functionality isn't ready for prime time as of 03/2025
# "containerLogs": {
#   "serviceAccount": {
#     "annotations": {
#       "eks.amazonaws.com/role-arn": "${module.iam_assumable_role_adot_container_logs.iam_role_arn}"
#     }
#   },
#   "pipelines": {
#     "logs": {
#       "cloudwatchLogs": {
#         "enabled": true
#       }
#     }
#   }
# }
