#################################################################################
# AWS EKS - Setting up EKS and and Allowing  Access from AWS Batch
#################################################################################

data "aws_eks_addon_version" "vpc-cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = var.kubernetes_version
}

data "aws_eks_addon_version" "kube-proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = var.kubernetes_version
}

data "aws_eks_addon_version" "eks-pod-identity-agent" {
  addon_name         = "eks-pod-identity-agent"
  kubernetes_version = var.kubernetes_version
}

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = var.kubernetes_version
}

data "aws_eks_addon_version" "metrics-server" {
  addon_name         = "metrics-server"
  kubernetes_version = var.kubernetes_version
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.2.0"

  # Name and version of the EKS cluster
  name               = var.name
  kubernetes_version = var.kubernetes_version

  # see: https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html
  endpoint_public_access  = true
  endpoint_private_access = true

  # Add the cluster creator account as an administrator
  enable_cluster_creator_admin_permissions = true

  # VPC and subnets where the EKS cluster will be created
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enable IAM Roles for Service Accounts (IRSA)
  enable_irsa = true

  # Disable creation of CloudWatch log group
  create_cloudwatch_log_group = false

  # These are unnecessary
  create_node_security_group = false
  create_security_group      = false

  # Required by vpc-cni
  iam_role_additional_policies = {
    "AmazonEKSVPCResourceController" = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  }

  # Define minimally required cluster add-ons - we'll add more in addons.tf
  addons = {
    coredns = {
      addon_version = data.aws_eks_addon_version.coredns.version
      configuration_values = jsonencode({
        tolerations = [
          # # Allow CoreDNS to run on the same nodes as the Karpenter controller
          # # for use during cluster creation when Karpenter nodes do not yet exist
          {
            key    = "karpenter.sh/controller"
            value  = "true"
            effect = "NoSchedule"
          }
        ]
      })
    }
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni = {
      before_compute = true
      most_recent    = true
      configuration_values = jsonencode({
        env = {
          ENABLE_POD_ENI           = "true"
          ENABLE_PREFIX_DELEGATION = "true"
        }
      })
    }
    ## NEED TO MOVE THIS TO HELM
    ## EKS ADDON doesn't seem to support adding '--kubelet-insecure-tls=true' to spec.containers.args
    # which is necessary until we determine a better setup for certificates
    metrics-server = {
      most_recent = true
    }
  }

  # Define managed node groups for the EKS cluster
  eks_managed_node_groups = {
    # The backend group will hold all non-Karpenter, non-NVIDIA system processes
    backend = {
      name           = "backend"
      instance_types = ["m5.xlarge"]

      min_size     = 1
      max_size     = 3
      desired_size = 1

      use_name_prefix          = false
      iam_role_name            = "${var.name}-backend-nodegroup-default"
      iam_role_use_name_prefix = false
      ebs_optimized            = true
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            # Kubecost requires at least 32GB storage
            volume_size = 100
            volume_type = "gp3"
          }
        }
      }

      metadata_options = {
        httpPutResponseHopLimit = 2
      }
      iam_role_additional_policies = {
        # Required by SSM
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        # Required by Container Insights
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        # Required to pull images from private ECR registries (if so desired)
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonEKSVPCResourceController     = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
        # Required for EFS
        AmazonEFSCSIDriverPolicy          = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
        AmazonPrometheusRemoteWriteAccess = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
      }

    }
    # Will host the Karpenter controller
    karpenter = {
      name           = "karpenter"
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m5a.4xlarge"]

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

      metadata_options = {
        httpPutResponseHopLimit = 2
      }

      iam_role_additional_policies = {
        # Required by SSM
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        # Required by Container Insights
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        # Required to pull images from private ECR registries (if so desired)
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonEKSVPCResourceController     = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
        # Required for EFS
        AmazonEFSCSIDriverPolicy          = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
        AmazonPrometheusRemoteWriteAccess = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
      }

    }

    # The gpuoperator group will hold the GPU enabled nodes required by NVIDIA GPU Operator
    gpuoperator = {
      name = "gpuoperator"
      # g4dn.xlarge is the cheapest compatible GPU-enabled instance
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

      metadata_options = {
        httpPutResponseHopLimit = 2
      }

      iam_role_additional_policies = {
        # Required by SSM
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        # Required by Container Insights
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        # Required to pull images from private ECR registries (if so desired)
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonEKSVPCResourceController     = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
        # Required for EFS
        AmazonEFSCSIDriverPolicy          = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
        AmazonPrometheusRemoteWriteAccess = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
      }

      labels = {
        "nvidia.com/gpu.deploy.gpu-feature-discovery" = "true"
        "nvidia.com/gpu.deploy.dcgm-exporter"         = "true"
        "nvidia.com/gpu.deploy.device-plugin"         = "true"
        "nvidia.com/gpu.deploy.operator-validator"    = "true"
      }

      # Only allow pods that request a GPU
      taints = {
        hasgpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        },
        criticaladdons = {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NO_SCHEDULE"
        }
      }
    }
  }
  # Tag the node security group for discovery by Karpenter
  node_security_group_tags = {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  }

  # # Define default IAM policies for the managed node groups

  # iam_role_additional_policies = {
  #   # Required by SSM
  #   AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  #   # Required by Container Insights
  #   CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  #   # Required to pull images from private ECR registries (if so desired)
  #   AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  #   AmazonEKSVPCResourceController     = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  # }

}

# Tag the primary security group of the EKS cluster for discovery by Karpenter
resource "aws_ec2_tag" "cluster_primary_security_group" {
  resource_id = module.eks.cluster_primary_security_group_id
  key         = "karpenter.sh/discovery"
  value       = module.eks.cluster_name
}
