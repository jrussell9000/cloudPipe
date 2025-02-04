#################################################################################
# AWS EKS - Setting up EKS and and Allowing  Access from AWS Batch
#################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~>20.33.0"

  cluster_name    = var.name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  cluster_compute_config = {
    enabled = true
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

}
