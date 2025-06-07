#################################################################################
# AWS EKS - Setting up EKS and and Allowing  Access from AWS Batch
#################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~>20.24.0"

  # Name and version of the EKS cluster
  cluster_name    = var.name
  cluster_version = var.kubernetes_version

  # see: https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Add the cluster creator account as an administrator
  enable_cluster_creator_admin_permissions = true

  # VPC and subnets where the EKS cluster will be created
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enable IAM Roles for Service Accounts (IRSA)
  enable_irsa = true

  # Disable creation of CloudWatch log group
  create_cloudwatch_log_group = false

  create_node_security_group    = false
  create_cluster_security_group = false

  # Define minimally required cluster add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
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
      before_compute = true
      most_recent    = true
      configuration_values = jsonencode({
        env = {
          ENABLE_POD_ENI                    = "true"
          ENABLE_PREFIX_DELEGATION          = "true"
          POD_SECURITY_GROUP_ENFORCING_MODE = "standard"
        }
        nodeAgent = {
          enablePolicyEventLogs = "true"
        }
        enableNetworkPolicy = "true"
      })
    }
  }

  # Define managed node groups for the EKS cluster
  eks_managed_node_groups = {
    # The backend group will hold all non-Karpenter, non-NVIDIA system processes
    backend = {
      name           = "backend"
      instance_types = ["m5.xlarge"]

      min_size     = 1
      max_size     = 5
      desired_size = 1

      use_name_prefix          = false
      iam_role_name            = "${var.name}-backend-nodegroup-default"
      iam_role_use_name_prefix = false
    }
    # Will host the Karpenter controller
    karpenter = {
      name           = "karpenter"
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m5.large"]

      min_size     = 1
      max_size     = 3
      desired_size = 1

      use_name_prefix          = false
      iam_role_name            = "${var.name}-karpentercontroller-nodegroup-default"
      iam_role_use_name_prefix = false

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

    # The gpuoperator group will hold the GPU enabled nodes required by NVIDIA GPU Operator
    gpuoperator = {
      name = "gpuoperator"
      # g4dn.xlarge is the cheapest, compatible GPU-enabled instance
      instance_types = ["g4dn.xlarge"]
      # The AL2023_x86_64_NVIDIA ami comes prepackaged with NVIDIA drivers
      ami_type = "AL2023_x86_64_NVIDIA"

      min_size     = 1
      max_size     = 3
      desired_size = 1

      use_name_prefix          = false
      iam_role_name            = "${var.name}-gpuoperator-nodegroup-default"
      iam_role_use_name_prefix = false

      # GPU-Operator requires a sizable root volume to hold the CUDA files
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

      labels = {
        "nvidia.com/gpu.deploy.gpu-feature-discovery" = "true"
        "nvidia.com/gpu.deploy.dcgm-exporter"         = "true"
        "nvidia.com/gpu.deploy.device-plugin"         = "true"
        "nvidia.com/gpu.deploy.operator-validator"    = "true"
      }

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

  # Tag the node security group for discovery by Karpenter
  node_security_group_tags = {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  }

  # Define default IAM policies for the managed node groups
  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Required by SSM
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      # Required by Container Insights
      CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      # Required to pull images from private ECR registries (if so desired)
      AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    }
  }
}

# Tag the primary security group of the EKS cluster for discovery by Karpenter
resource "aws_ec2_tag" "cluster_primary_security_group" {
  resource_id = module.eks.cluster_primary_security_group_id
  key         = "karpenter.sh/discovery"
  value       = module.eks.cluster_name
}
