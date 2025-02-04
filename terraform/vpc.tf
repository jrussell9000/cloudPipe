#################################################################################
# AWS VPC - Networking
#################################################################################

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = ">= 5.0"

  name = "${var.name}_vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true
  #-------------------------------

  # Manage so we can name
  # manage_default_network_acl    = true
  # default_network_acl_tags      = { Name = "${var.cluster_name}-default" }
  # manage_default_route_table    = true
  # default_route_table_tags      = { Name = "${var.cluster_name}-default" }
  # manage_default_security_group = true
  # default_security_group_tags   = { Name = "${var.cluster_name}-default" }

  public_subnet_tags = {
    "kubernetes.io/role/alb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-alb" = 1
    # Karpenter requires us to specify a subnet tag so we can select the subnet(s) where nodes will be created
    "karpenter.sh/discovery" = var.name
  }
}
