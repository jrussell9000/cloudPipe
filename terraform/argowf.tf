################################################################################
# Argo-Workflows
################################################################################
# Argo Workflows Server IAM Policy
# https://github.com/open-metadata/openmetadata-deployment/blob/main/terraform/aws/argowf_irsa.tf

/**************
* Server IRSA *
***************/
# Service account used by the Argo Workflows Server
module "argo_workflows_server_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.22"

  role_name = "argo-workflows-server"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.argo_workflows_namespace}:argo-workflows-server"]
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

resource "aws_iam_policy" "argo_workflows_controller" {
  name   = "argo-workflows-controller-policy"
  policy = data.aws_iam_policy_document.argo_workflows_controller.json
}

# Service account used by the Argo Workflows Controller
module "argo_workflows_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.22"

  role_name = "argo-workflows-controller"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.argo_workflows_namespace}:argo-workflows-controller"]
    }
  }
}


/******************************************
* Account for accessing the for S3 Bucket *
*******************************************/

# Allow full access to workflow storage bucket using AWS S3 IRSA approach
# documented here: https://argo-workflows.readthedocs.io/en/latest/configure-artifact-repository/#aws-s3-irsa

# Create an IRSA account for S3 access (include iam_policy) and add the 

# Create IAM policy for accessing bucket
resource "aws_iam_policy" "s3access" {
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Effect" : "Allow",
      "Action" : [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource" : "arn:aws:s3:::brc-abcd/*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket"
        ],
        "Resource" : "arn:aws:s3:::brc-abcd"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetBucketLocation"
        ],
        "Resource" : "arn:aws:s3:::*"
    }]
  })
}

# Create IRSA role for S3 access that will carry the policy defined above
module "argo_workflows_s3_access" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.22"

  role_name = "argo-workflows-s3-access"

  # Provide this account read/write access to the S3 bucket
  role_policy_arns = {
    argos3access = aws_iam_policy.s3access.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.argo_workflows_namespace}:argo-workflows-runner"]
    }
  }
}

# Next, add the arn of the IRSA role as an annotation to the 
# workflow service account in argo-workflows-config.tftpl
# e.g., eks.amazonaws.com/role-arn: ${ argos3accessarn }

/********************
* Helm Installation *
*********************/

resource "helm_release" "argo_workflows_release" {
  depends_on = [module.argo_workflows_server_irsa,
    module.argo_workflows_controller_irsa,
  module.argo_workflows_s3_access]
  name             = lower(local.name)
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-workflows"
  namespace        = "argo-workflows"
  create_namespace = true
  cleanup_on_fail  = true

  values = [
    templatefile("${path.module}/helm-values/argo-workflows-values.tftpl",
      {
        # Specifying the IRSA accounts to use
        argos3accessarn  = module.argo_workflows_s3_access.iam_role_arn
        controllerIAMarn = module.argo_workflows_controller_irsa.iam_role_arn
        controllerSAname = module.argo_workflows_controller_irsa.iam_role_name
        serverIAMarn     = module.argo_workflows_server_irsa.iam_role_arn
        serverSAname     = module.argo_workflows_server_irsa.iam_role_name
    })
  ]
}
