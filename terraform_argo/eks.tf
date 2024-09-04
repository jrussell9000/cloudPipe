#################################################################################
# AWS EKS - Setting up EKS and and Allowing  Access from AWS Batch
#################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.23.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # This appears to be required (for now) to get Helm to recognize the K8s cluster
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id = module.vpc.vpc_id

  subnet_ids = module.vpc.private_subnets

  create_cloudwatch_log_group   = false
  create_cluster_security_group = false
  create_node_security_group    = false



  # We want our 'creator' account to be able to manage the cluster
  enable_cluster_creator_admin_permissions = true

  # Enable IRSA for service accounts
  enable_irsa = true

  access_entries = {
    # One access entry with a policy associated
    netidadmin = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/NetIDAdministratorAccess"

      policy_associations = {
        clusteradmin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
    ebs_optimized = true
    # This block device is used only for the root volume. Adjust volume according to your size.
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size = 50
          volume_type = "gp3"
        }
      }
    }
  }

  eks_managed_node_groups = {
    # NVIDIA GPU-Operator REQUIRES a GPU instance to run (for now)
    eksControl_gpuOnly = {
      name = "eksControl_gpu"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      # subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
      #   substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
      # )
      # Smallest GPU-enabled instance
      instance_types = ["g4dn.xlarge", "g6.xlarge"]
      min_size       = 1
      max_size       = 10
      desired_size   = 1
      # Untouched AL2 Accelerated EKS Optimized Image w 30GB root storage
      ami_id   = "ami-09fcc208f4f6394d4"
      ami_type = "CUSTOM"
      # Run post-creation setup processes - required for non-AL (custom) instances
      enable_bootstrap_user_data = true
      # bootstrap_extra_args = "--container-runtime nvidia-container-runtime"
    }
  }

  fargate_profiles = {
    karpenter = {
      selectors = [
        { namespace = "karpenter" }
      ]
    }
    kube_system = {
      name = "kube-system"
      selectors = [
        { namespace = "kube-system" }
      ]
    }
    argo = {
      name = "argo"
      selectors = [
        { namespace = "argo*",
          labels = {
            "app.kubernetes.io/managed-by" = "Helm"
          }
        }
      ]
    }
  }
  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  })
}

module "aws-auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = "~> 20.0"

  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    },
  ]
}
