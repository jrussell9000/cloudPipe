#################################################################################
# AWS VPC - Networking
#################################################################################

# Create a VPC that will support Batch on EKS
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.eks_vpc_name
  cidr = var.eks_vpc_cidr
  azs  = local.azs

  public_subnets = var.eks_public_subnets
  private_subnets = var.eks_private_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

}

