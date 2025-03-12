################################################################################
# Argo-Workflows
################################################################################
# Argo Workflows Server IAM Policy
# https://github.com/open-metadata/openmetadata-deployment/blob/main/terraform/aws/argowf_irsa.tf

resource "kubernetes_namespace" "argo_workflows" {
  metadata {
    name = var.argo_workflows_namespace
  }
}

#---------------------------------------------------------------
# Argo Workflows Database
#---------------------------------------------------------------

resource "random_password" "argo_workflows_db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

// Create a DB subnet to provision the database. 
resource "aws_db_subnet_group" "argo_workflows" {
  subnet_ids = module.vpc.public_subnets
}

resource "aws_security_group" "argo_workflows_db" {
  name_prefix = "${var.name}-mysql-sg-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    cidr_blocks = [
      var.vpc_cidr
    ]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Argo Workflows Database
resource "aws_db_instance" "argo_workflows_db" {
  allocated_storage = 10
  engine            = "mysql"
  instance_class    = var.argo_workflows_db_class

  db_name              = var.argo_workflows_db_name
  identifier           = var.argo_workflows_db_name
  username             = var.argo_workflows_db_username
  password             = random_password.argo_workflows_db_password.result
  multi_az             = false
  db_subnet_group_name = aws_db_subnet_group.argo_workflows.name
  vpc_security_group_ids = [
    aws_security_group.argo_workflows_db.id
  ]
  backup_retention_period = 7
  storage_type            = "gp2"
  # Terraform won't destroy RDS instances unless deletion protection and final snapshot are disabled
  deletion_protection   = false
  skip_final_snapshot   = true
  max_allocated_storage = 1000
  publicly_accessible   = false
}

#---------------------------------------------------------------
# Argo Workflows Secrets
#---------------------------------------------------------------

resource "aws_kms_key" "secrets" {
  enable_key_rotation = true
}

resource "kubectl_manifest" "cluster_secretstore" {
  yaml_body  = <<-YAML
    apiVersion: external-secrets.io/v1beta1
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
  depends_on = [module.eks_blueprints_addons]
}

resource "aws_secretsmanager_secret" "argo_workflows_db_secret" {
  recovery_window_in_days        = 7
  kms_key_id                     = aws_kms_key.secrets.arn
  name_prefix                    = "${var.name}-argo-workflows-db-secret-"
  force_overwrite_replica_secret = true

  depends_on = [aws_kms_key.secrets]
}

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

resource "kubectl_manifest" "argo_workflows_db_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
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

  depends_on = [kubernetes_namespace.argo_workflows,
  aws_secretsmanager_secret.argo_workflows_db_secret]

}

#---------------------------------------------------------------
# Argo Workflows IRSA and Policies
#---------------------------------------------------------------

# Create an IRSA role for the Argo Workflows server
module "argo_workflows_serverIRSA" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.22"

  role_name = var.argo_workflows_serverIRSA_name

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.argo_workflows_namespace}:${var.argo_workflows_serverIRSA_name}"]
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
module "argo_workflows_controllerIRSA" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.22"

  role_name = var.argo_workflows_controllerIRSA_name

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.argo_workflows_namespace}:${var.argo_workflows_controllerIRSA_name}"]
    }
  }
}

/*************
* S3 Access  *
**************/

# Allow full access to workflow storage bucket using AWS S3 IRSA approach
# documented here: https://argo-workflows.readthedocs.io/en/latest/configure-artifact-repository/#aws-s3-irsa

# Create IAM policy for getting bucket location, listing contents, and reading/writing

data "aws_iam_policy_document" "argo_workflows_s3access" {
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

resource "aws_iam_policy" "argo_workflows_s3access" {
  name   = "argo_workflows-s3access-policy"
  policy = data.aws_iam_policy_document.argo_workflows_s3access.json
}

# Create an IRSA role that will be allowed to access the S3 bucket
module "argo_workflows_s3accessIRSA" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.22"

  role_name = var.argo_workflows_s3accessIRSA_name

  # Provide this account read/write access to the S3 bucket
  role_policy_arns = {
    argos3access = aws_iam_policy.argo_workflows_s3access.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.argo_workflows_namespace}:${var.argo_workflows_s3accessIRSA_name}"]
    }
  }
}

/********************
* Helm Installation *
*********************/

# Be sure to add the arn of the IRSA role as an annotation to the 
# workflow service account in the argo workflows config (e.g., argo-workflows-values.yaml)

resource "helm_release" "argo_workflows_release" {

  # Terraform doesn't automagically incorporate these dependencies
  # (possibly because they're in templatefile?), so they need to be
  # added explicitly.
  depends_on = [module.argo_workflows_serverIRSA,
    module.argo_workflows_controllerIRSA,
    module.argo_workflows_s3accessIRSA,
    aws_secretsmanager_secret.argo_workflows_db_secret,
    resource.kubectl_manifest.argo_workflows_db_secret,
    resource.aws_db_instance.argo_workflows_db
  ]
  name             = "argo-workflows"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-workflows"
  namespace        = "argo-workflows"
  create_namespace = false
  wait             = true

  values = [
    templatefile("${path.module}/helm-values/argo/workflows/argo-workflows-values.yaml",
      {
        # Specifying the namespace and log bucket
        argo_workflows_namespace = var.argo_workflows_namespace
        argo_workflows_bucket    = var.argo_workflows_bucket
        region                   = var.region

        # Specifying the IRSA accounts to use
        argo_workflows_s3accessIRSA_arn    = module.argo_workflows_s3accessIRSA.iam_role_arn
        argo_workflows_s3accessIRSA_name   = module.argo_workflows_s3accessIRSA.iam_role_name
        argo_workflows_controllerIRSA_arn  = module.argo_workflows_controllerIRSA.iam_role_arn
        argo_workflows_controllerIRSA_name = module.argo_workflows_controllerIRSA.iam_role_name
        argo_workflows_serverIRSA_arn      = module.argo_workflows_serverIRSA.iam_role_arn
        argo_workflows_serverIRSA_name     = module.argo_workflows_serverIRSA.iam_role_name

        # Providing connection details for the database
        argo_workflows_db_host        = aws_db_instance.argo_workflows_db.address
        argo_workflows_db_name        = aws_db_instance.argo_workflows_db.db_name
        argo_workflows_db_port        = aws_db_instance.argo_workflows_db.port
        argo_workflows_db_secret_name = aws_secretsmanager_secret.argo_workflows_db_secret.name
        argo_workflows_db_table_name  = var.argo_workflows_db_table_name
    })
  ]
}
