################################################################################
# Argo-Workflows
################################################################################
# Argo Workflows Server IAM Policy
# https://github.com/open-metadata/openmetadata-deployment/blob/main/terraform/aws/argowf_irsa.tf

/*****************************************************
* Argo Workflows Server - Policies and IRSA Creation *
******************************************************/

# Is the S3 policy necessary?
# data "aws_iam_policy_document" "argo_workflows_server" {
#   statement {
#     sid = "ListBuckets"
#     actions = [
#       "s3:ListBucket",
#       "s3:GetBucketLocation"
#     ]
#     resources = ["arn:aws:s3:::brc-abcd"]
#   }
#   statement {
#     sid       = "S3RO"
#     actions   = ["s3:GetObject"]
#     resources = ["arn:aws:s3:::brc-abcd/*"]
#   }
# }

# resource "aws_iam_policy" "argo_workflows_server" {
#   name   = "argo-workflows-server-policy"
#   policy = data.aws_iam_policy_document.argo_workflows_server.json
# }

module "argo_workflows_server_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.22"

  role_name = "argo-workflows-server-role"

  role_policy_arns = {
    argos3access = aws_iam_policy.argo_workflow_s3.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["argo-workflows:${lower(var.argo_workflows_server_serviceaccount)}"]
    }
  }
}

/*********************************************************
* Argo Workflows Controller - Policies and IRSA Creation *
**********************************************************/

# Is the S3 policy necessary?
# data "aws_iam_policy_document" "argo_workflows_controller" {
#   statement {
#     sid = "ListBuckets"
#     actions = [
#       "s3:ListBucket",
#       "s3:GetBucketLocation"
#     ]
#     resources = ["arn:aws:s3:::brc-abcd"]
#   }

#   statement {
#     sid = "S3RW"
#     actions = [
#       "s3:PutObject",
#       "s3:GetObject",
#       "s3:DeleteObject"
#     ]
#     resources = ["arn:aws:s3:::brc-abcd/*"]
#   }
# }

# resource "aws_iam_policy" "argo_workflows_controller" {
#   name   = "argo-workflows-controller-policy"
#   policy = data.aws_iam_policy_document.argo_workflows_controller.json
# }

module "argo_workflows_controller_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "argo-workflows-controller-role"
  role_policy_arns = {
    argos3access = aws_iam_policy.argo_workflow_s3.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["argo-workflows:${lower(var.argo_workflows_controller_serviceaccount)}"]
    }
  }
}

/***************************************
* Argo Workflows - Access to S3 Bucket *
****************************************/

# Allow full access to workflow storage bucket
data "aws_iam_policy_document" "argo_workflow_s3" {
  statement {
    effect  = "Allow"
    actions = ["s3:*"]
    resources = ["arn:aws:s3:::brc-abcd/*",
    "arn:aws:s3:::brc-abcd"]
  }
}

resource "aws_iam_policy" "argo_workflow_s3" {
  name   = "argo_workflow_s3_policy"
  policy = data.aws_iam_policy_document.argo_workflow_s3.json
}

/***************************************
* Argo Workflows - Access to S3 Bucket *
****************************************/

resource "helm_release" "argo_workflow_release" {
  depends_on = [module.argo_workflows_server_irsa,
  module.argo_workflows_controller_irsa]
  name             = lower(local.name)
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-workflows"
  namespace        = "argo-workflows"
  create_namespace = true
  cleanup_on_fail  = true

  values = [
    templatefile("${path.module}/helm-values/argo-workflows-config.tftpl",
      {
        controllerSAname = module.argo_workflows_controller_irsa.iam_role_name
        serverSAname     = module.argo_workflows_server_irsa.iam_role_name
        controllerIAMarn = module.argo_workflows_controller_irsa.iam_role_arn
        serverIAMarn     = module.argo_workflows_server_irsa.iam_role_arn
    })
  ]
}
