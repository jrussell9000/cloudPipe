################################################################################
# Argo-Workflows
################################################################################
# Argo Workflows Server IAM Policy
# https://github.com/open-metadata/openmetadata-deployment/blob/main/terraform/aws/argowf_irsa.tf

# Creating the Argo Workflows namespace
resource "kubernetes_namespace_v1" "argo_workflows" {
  metadata {
    name = var.argo_workflows_namespace
  }
}

#---------------------------------------------------------------
# Argo Workflows Database
#---------------------------------------------------------------

# Generating a random password for the database
resource "random_password" "argo_workflows_db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Creating a DB subnet where we'll provision the database.
resource "aws_db_subnet_group" "argo_workflows_db" {
  subnet_ids = module.vpc.public_subnets
}

resource "aws_security_group" "argo_workflows_db" {
  name_prefix = "${var.name}-mysql-sg-"
  vpc_id      = module.vpc.vpc_id
  description = "Security group containing ingress rule for the Argo Workflows MySQL database."
}

resource "aws_vpc_security_group_ingress_rule" "argo_workflows_db_myip" {
  security_group_id = aws_security_group.argo_workflows_db.id
  cidr_ipv4         = "${chomp(data.http.myip.response_body)}/32"
  from_port         = 3306
  ip_protocol       = "tcp"
  to_port           = 3306
}

resource "aws_vpc_security_group_ingress_rule" "argo_workflows_db" {
  security_group_id = aws_security_group.argo_workflows_db.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 3306
  ip_protocol       = "tcp"
  to_port           = 3306
}

resource "aws_vpc_security_group_egress_rule" "argo_workflows_db" {
  security_group_id = aws_security_group.argo_workflows_db.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# Lookup the default version for the engine. Db2 Standard Edition is `db2-se`, Db2 Advanced Edition is `db2-ae`.
data "aws_rds_engine_version" "mysql" {
  engine = "mysql" #Standard Edition
  # default_only = true
  latest = true
}

# Creating the Argo Workflows database
resource "aws_db_instance" "argo_workflows_db" {
  allocated_storage = 20
  engine            = data.aws_rds_engine_version.mysql.engine
  engine_version    = data.aws_rds_engine_version.mysql.version
  instance_class    = var.argo_workflows_db_class

  db_name              = var.argo_workflows_db_name
  identifier           = var.argo_workflows_db_name
  username             = var.argo_workflows_db_username
  password             = random_password.argo_workflows_db_password.result
  multi_az             = false
  db_subnet_group_name = aws_db_subnet_group.argo_workflows_db.name
  vpc_security_group_ids = [
    aws_security_group.argo_workflows_db.id
  ]
  backup_retention_period = 7
  storage_type            = "gp3"
  max_allocated_storage   = 1000
  publicly_accessible     = true
  # Terraform won't destroy RDS instances unless deletion protection and final snapshot are disabled
  deletion_protection = false
  skip_final_snapshot = true
  storage_encrypted   = true

  enabled_cloudwatch_logs_exports = ["error"]
}

# Adding the Argo Workflows database access parameters as a new K8s secret (in AWS SecretsManager)
resource "aws_kms_key" "secrets" {
  enable_key_rotation = true
}

# Setting up a Cluster Secret Store to hold the Argo Workflows database secret
resource "kubectl_manifest" "cluster_secretstore" {
  yaml_body  = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ClusterSecretStore
    metadata:
      name: external-secrets-clusterstore
      namespace: external-secrets
    spec:
      provider:
        aws:
          service: SecretsManager
          region: us-east-2
          auth:
            jwt:
              serviceAccountRef:
                name: external-secrets-sa
                namespace: "external-secrets"
  YAML
  depends_on = [helm_release.external_secrets]
}

# Creating a new secret in AWS Secrets Manager
resource "aws_secretsmanager_secret" "argo_workflows_db_secret" {
  recovery_window_in_days        = 7
  kms_key_id                     = aws_kms_key.secrets.arn
  name_prefix                    = "${var.name}-argo-workflows-db-secret-"
  force_overwrite_replica_secret = true

  depends_on = [aws_kms_key.secrets]
}

# Adding data to the new secret
resource "aws_secretsmanager_secret_version" "argo_workflows_db_secret" {
  secret_id = aws_secretsmanager_secret.argo_workflows_db_secret.id
  secret_string = jsonencode({
    username = aws_db_instance.argo_workflows_db.username
    password = aws_db_instance.argo_workflows_db.password
    database = aws_db_instance.argo_workflows_db.db_name
    host     = aws_db_instance.argo_workflows_db.address
    port     = tostring(aws_db_instance.argo_workflows_db.port)
  })
  depends_on = [aws_db_instance.argo_workflows_db]
}

# Creating the secret in EKS
resource "kubectl_manifest" "argo_workflows_db_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: ${aws_secretsmanager_secret.argo_workflows_db_secret.name}
      namespace: ${var.argo_workflows_namespace}
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: external-secrets-clusterstore
        kind: ClusterSecretStore
      dataFrom:
      - extract:
          key: ${aws_secretsmanager_secret.argo_workflows_db_secret.name}
  YAML

  depends_on = [kubernetes_namespace_v1.argo_workflows,
    aws_secretsmanager_secret.argo_workflows_db_secret,
  resource.helm_release.external_secrets]
}

#---------------------------------------------------------------
# Argo Workflows IRSA and Policies
#---------------------------------------------------------------

# Creating an IRSA role for the Argo Workflows server
module "argo_workflows_server_IRSA" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~>6.0"

  name            = var.argo_workflows_server_IRSA_name
  use_name_prefix = false

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.argo_workflows_namespace}:${var.argo_workflows_server_IRSA_name}"]
    }
  }
}

/*****************
* Controller IRSA *
******************/

# Is this S3 policy necessary?
data "aws_iam_policy_document" "argo_workflows_controller" {
  statement {
    sid = "ListBuckets"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = ["arn:aws:s3:::${var.argo_workflows_bucket}"]
  }

  statement {
    sid = "S3RW"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = ["arn:aws:s3:::${var.argo_workflows_bucket}/*"]
  }
}

resource "aws_iam_policy" "argo_workflows_controller" {
  name   = "argo_workflows-controller-policy"
  policy = data.aws_iam_policy_document.argo_workflows_controller.json
}

# Create an IRSA role for the Argo Workflows controller
module "argo_workflows_controller_IRSA" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~>6.0"

  name            = var.argo_workflows_controller_IRSA_name
  use_name_prefix = false

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.argo_workflows_namespace}:${var.argo_workflows_controller_IRSA_name}"]
    }
  }
}

# Enabling Argo Workflows metrics by creating a metrics service and a service monitor per the documentation
# Note: There's an option to enable this in the helm values, but the documentation doesn't mention it(?)
# Ref: https://argo-workflows.readthedocs.io/en/latest/metrics/#prometheus-scraping
resource "kubernetes_service" "argo-workflows-controller-metrics" {
  metadata {
    name = "argo-workflows-controller-metrics"
    labels = {
      app = "workflow-controller"
    }
    namespace = "argo-workflows"
  }
  spec {
    selector = {
      app = "workflow-controller"
    }
    port {
      name        = "metrics"
      port        = 9090
      protocol    = "TCP"
      target_port = 9090
    }
    cluster_ip = "None"
  }
}

resource "kubectl_manifest" "argo-workflows-service-monitor" {
  yaml_body = <<YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: argo-workflows
      namespace: argo-workflows
    spec:
      endpoints:
      - port: metrics
      selector:
        matchLabels:
          app: workflow-controller
  YAML

  depends_on = [helm_release.prometheus_crds]
}

/*************
* S3 Access  *
**************/

# Allow full access to workflow storage bucket using AWS S3 IRSA approach
# documented here: https://argo-workflows.readthedocs.io/en/latest/configure-artifact-repository/#aws-s3-irsa

# Create IAM policy for getting bucket location, listing contents, and reading/writing

data "aws_iam_policy_document" "argo_workflows_runner" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = ["arn:aws:s3:::${var.argo_workflows_bucket}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = ["arn:aws:s3:::${var.argo_workflows_bucket}"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation"
    ]
    resources = ["arn:aws:s3:::*"]
  }
}

resource "aws_iam_policy" "argo_workflows_runner" {
  name   = "argo_workflows-runner-policy"
  policy = data.aws_iam_policy_document.argo_workflows_runner.json
}

# Create an IRSA role that will be allowed to access the S3 bucket
module "argo_workflows_runner_IRSA" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~>6.0"

  name            = var.argo_workflows_runner_IRSA_name
  use_name_prefix = false

  # Provide this account read/write access to the S3 bucket
  policies = {
    argorunner          = aws_iam_policy.argo_workflows_runner.arn
    fsxfullaccesspolicy = "arn:aws:iam::aws:policy/AmazonFSxFullAccess"
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.argo_workflows_namespace}:${var.argo_workflows_runner_IRSA_name}"]
    }
  }
}

# Helm will create this for us (below)
# resource "kubernetes_service_account_v1" "argo_workflows_runner" {
#   metadata {
#     name      = var.argo_workflows_runner_IRSA_name
#     namespace = var.argo_workflows_namespace
#     annotations = {
#       "eks.amazonaws.com/role-arn" = module.argo_workflows_runner_IRSA.iam_role_arn
#     }
#   }
#   depends_on = [kubernetes_namespace_v1.argo_workflows]
# }

# Create a role with the necessary permissions for running Argo Workflows
resource "kubernetes_role_v1" "argo_workflows_runner" {
  metadata {
    name      = var.argo_workflows_runner_IRSA_name
    namespace = var.argo_workflows_namespace
  }

  rule {
    api_groups = ["argoproj.io"]
    resources  = ["workflows", "workflowtemplates", "workflowtaskresults"]
    verbs      = ["*"]
  }

  depends_on = [kubernetes_namespace_v1.argo_workflows]
}

# Bind the role to the service account created above (IRSA)
resource "kubernetes_role_binding_v1" "argo_workflows_runner" {
  metadata {
    name      = "${var.argo_workflows_runner_IRSA_name}-role-binding"
    namespace = var.argo_workflows_namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = var.argo_workflows_runner_IRSA_name
  }
  subject {
    kind      = "ServiceAccount"
    name      = var.argo_workflows_runner_IRSA_name
    namespace = var.argo_workflows_namespace
  }
}

resource "aws_security_group" "argo_workflows_server_lb" {
  name   = "argo_workflows_lb"
  vpc_id = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "argo_workflows_server_lb" {
  security_group_id = aws_security_group.argo_workflows_server_lb.id
  cidr_ipv4         = "${chomp(data.http.myip.response_body)}/32"
  from_port         = 2746
  ip_protocol       = "tcp"
  to_port           = 2746
}

resource "aws_vpc_security_group_egress_rule" "argo_workflows_server_lb" {
  security_group_id = aws_security_group.argo_workflows_server_lb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

/********************
* Helm Installation *
*********************/
resource "helm_release" "argo_workflows_release" {

  # Terraform doesn't automagically incorporate these dependencies
  # (possibly because they're referenced in a call to templatefile?), so they need to be
  # added explicitly.
  depends_on = [module.argo_workflows_server_IRSA,
    module.argo_workflows_controller_IRSA,
    module.argo_workflows_runner_IRSA,
    aws_secretsmanager_secret.argo_workflows_db_secret,
    resource.kubectl_manifest.argo_workflows_db_secret,
    resource.aws_db_instance.argo_workflows_db,
    helm_release.prometheus_crds
  ]
  name             = "argo-workflows"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-workflows"
  namespace        = "argo-workflows"
  create_namespace = false
  wait             = false

  values = [
    templatefile("${path.module}/helm-values/argo/workflows/argo-workflows-values.yaml",
      {
        # Specifying the namespace and log bucket
        argo_workflows_namespace = var.argo_workflows_namespace
        argo_workflows_bucket    = var.argo_workflows_bucket
        region                   = var.region

        # Specifying the IRSA accounts to use
        argo_workflows_runner_IRSA_arn      = module.argo_workflows_runner_IRSA.arn
        argo_workflows_runner_IRSA_name     = module.argo_workflows_runner_IRSA.name
        argo_workflows_controller_IRSA_arn  = module.argo_workflows_controller_IRSA.arn
        argo_workflows_controller_IRSA_name = module.argo_workflows_controller_IRSA.name
        argo_workflows_server_IRSA_arn      = module.argo_workflows_server_IRSA.arn
        argo_workflows_server_IRSA_name     = module.argo_workflows_server_IRSA.name

        # Providing connection details for the database
        argo_workflows_db_host        = aws_db_instance.argo_workflows_db.address
        argo_workflows_db_name        = aws_db_instance.argo_workflows_db.db_name
        argo_workflows_db_port        = aws_db_instance.argo_workflows_db.port
        argo_workflows_db_secret_name = aws_secretsmanager_secret.argo_workflows_db_secret.name
        argo_workflows_db_table_name  = var.argo_workflows_db_table_name

        argo_frontend_securitygroup = aws_security_group.argo_workflows_server_lb.id
    })
  ]
}
