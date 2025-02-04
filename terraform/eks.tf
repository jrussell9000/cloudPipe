#################################################################################
# AWS EKS - Setting up EKS and and Allowing  Access from AWS Batch
#################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~>20.24.0"

  cluster_name    = var.name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enable IRSA for service accounts
  enable_irsa = true

  create_cloudwatch_log_group   = false
  create_cluster_security_group = false
  create_node_security_group    = false

  cluster_addons = {
    coredns = {
      configuration_values = jsonencode({
        tolerations = [
          # Allow CoreDNS to run on the same nodes as the Karpenter controller
          # for use during cluster creation when Karpenter nodes do not yet exist
          {
            key    = "karpenter.sh/controller"
            value  = "true"
            effect = "NoSchedule"
          }
        ]
      })
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  # DO NOT TRY THIS!!! Causes FAR too many problems to be worth it
  # fargate_profiles = {
  #   karpenter = {
  #     selectors = [
  #       { namespace = "karpenter" }
  #     ]
  #   }
  #   kube-system = {
  #     selectors = [
  #       { namespace = "kube-system" }
  #     ]
  #   }
  # }

  eks_managed_node_groups = {
    backend = {
      name           = "backend"
      instance_types = ["m5.xlarge"]
      min_size       = 1
      max_size       = 5
      desired_size   = 1
    }

    karpenter = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m5.large"]

      min_size     = 1
      max_size     = 3
      desired_size = 1

      labels = {
        # Used to ensure Karpenter runs on nodes that it does not manage
        "karpenter.sh/controller" = "true"
      }

      taints = {
        # The pods that do not tolerate this taint should run on nodes
        # created by Karpenter
        karpenter = {
          key    = "karpenter.sh/controller"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }

    gpuoperator = {
      name           = "gpuoperator"
      instance_types = ["g4dn.xlarge"]
      ami_type       = "AL2023_x86_64_NVIDIA"
      min_size       = 1
      max_size       = 3
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
      capacity_type = "SPOT"

      # Only allow pods that request a GPU
      taints = [
        {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        },
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NO_SCHEDULE"
        }
      ]
    }
  }

  # This probably isn't necessary, but just in case
  node_security_group_tags = {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Required by Container Insights
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      CloudWatchAgentServerPolicy  = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    }
  }
}

# Karpenter requires we select a security group using a tag
resource "aws_ec2_tag" "cluster_primary_security_group" {
  resource_id = module.eks.cluster_primary_security_group_id
  key         = "karpenter.sh/discovery"
  value       = module.eks.cluster_name
}
