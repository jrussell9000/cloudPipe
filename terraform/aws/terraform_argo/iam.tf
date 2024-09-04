################################################################################
# Argo-Workflows
################################################################################
# Argo Workflows Server IAM Policy
# https://github.com/open-metadata/openmetadata-deployment/blob/main/terraform/aws/argowf_irsa.tf
data "aws_iam_policy_document" "argowf_server" {
  statement {
    sid = "ListBuckets"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = ["arn:aws:s3:::brc-abcd"]
  }
  statement {
    sid       = "S3RO"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::brc-abcd/*"]
  }
}

resource "aws_iam_policy" "argowf_server" {
  name   = "argowf-server-policy"
  policy = data.aws_iam_policy_document.argowf_server.json
}

module "argo_workflows_server_irsa_aws" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.14"

  role_name = "argowf-server-role"

  role_policy_arns = {
    "S3RO" = aws_iam_policy.argowf_server.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${lower(var.argowf_namespace)}:${lower(var.argowf_server_serviceaccount)}"]
    }
  }
}

data "aws_iam_policy_document" "argowf_controller" {
  statement {
    sid = "ListBuckets"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = ["arn:aws:s3:::brc-abcd"]
  }

  statement {
    sid = "S3RW"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = ["arn:aws:s3:::brc-abcd/*"]
  }
}

resource "aws_iam_policy" "argowf_controller" {
  name   = "argowf-controller-policy"
  policy = data.aws_iam_policy_document.argowf_controller.json
}

module "argo_workflows_controller_irsa_aws" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "argo-workflows-controller-role"
  role_policy_arns = {
    "S3RW" = aws_iam_policy.argowf_controller.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${lower(var.argowf_namespace)}:${lower(var.argowf_controller_serviceaccount)}"]
    }
  }
}
