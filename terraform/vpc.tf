#################################################################################
# AWS VPC - Networking
#################################################################################

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.name}_vpc"
  cidr = var.vpc_cidr

  # Should change this to a single availability zone
  azs                   = local.azs
  private_subnets       = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets        = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]
  public_subnet_suffix  = "SubnetPublic"
  private_subnet_suffix = "SubnetPrivate"

  enable_nat_gateway   = true
  create_igw           = true
  enable_dns_hostnames = true
  single_nat_gateway   = true
  #-------------------------------

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${var.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${var.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${var.name}-default" }


  # Flow logs required by SP 800-171
  create_flow_log_cloudwatch_iam_role             = true
  create_flow_log_cloudwatch_log_group            = true
  enable_flow_log                                 = true
  flow_log_cloudwatch_log_group_retention_in_days = 7

  public_subnet_tags = {
    # Required subnet tag for public-facing application load balancer
    "kubernetes.io/role/alb" = 1
  }

  private_subnet_tags = {
    # Required subnet tag for private-facing application load balancer
    "kubernetes.io/role/internal-alb" = 1
    # Karpenter requires us to specify a subnet tag so we can select the subnet(s) where nodes will be created
    "karpenter.sh/discovery" = var.name
  }
}
