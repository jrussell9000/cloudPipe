#################################################################################
# AWS EKS - Setting up EKS and and Allowing  Access from AWS Batch
#################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~>20.24.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enable IRSA for service accounts
  enable_irsa = true

  create_cloudwatch_log_group   = false
  create_cluster_security_group = false
  create_node_security_group    = false

  # access_entries = {
  #   netidadmin = {
  #     kubernetes_groups = []
  #     principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/NetIDAdministratorAccess"
  #     policy_associations = {
  #       clusteradmin = {
  #         policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  #         access_scope = {
  #           type = "cluster"
  #         }
  #       }
  #     }
  #   }
  # }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      AmazonEBSCSIDriverPolicy     = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  eks_managed_node_groups = {
    karpenter = {
      name           = "karpenter"
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1

      labels = {
        # Used to ensure Karpenter runs on nodes that it does not manage
        "karpenter.sh/controller" = "true"
      }

      taints = {
        # The pods that do not tolerate this taint should run on nodes
        # created by Karpenter
        addons = {
          key    = "karpenter.sh/controller"
          value  = "true"
          effect = "NO_SCHEDULE"
        },
      }
    }

    gpuoperator = {
      name           = "gpuoperator"
      instance_types = ["g4dn.xlarge"]
      ami_type       = "AL2_x86_64_GPU"
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      # GPU-Operator requires a sizable root volume to hold CUDA
      ebs_optimized = true
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 20
            volume_type = "gp2"
          }
        }
      }
    }
  }
}

# Karpenter requires we select a security group using a tag
resource "aws_ec2_tag" "cluster_primary_security_group" {
  resource_id = module.eks.cluster_primary_security_group_id
  key         = "karpenter.sh/discovery"
  value       = module.eks.cluster_name
}

# resource "kubernetes_namespace" "monitoring" {
#   metadata {
#     annotations = {
#       name = "monitoring-ns"
#     }
#     name = "monitoring"
#   }
# }
