#################################################################################
# AWS EKS - Setting up EKS and and Allowing  Access from AWS Batch
#################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id

  subnet_ids = module.vpc.private_subnets

  # Need to find a way to use Helm in terraform without needing public access
  # For now, the line below is required to use helm via eks_addons_blueprints
  cluster_endpoint_public_access = true

  # We want our 'creator' account to be able to manage the cluster
  enable_cluster_creator_admin_permissions = true

  access_entries = {
    # One access entry with a policy associated
    netidadmin = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/NetIDAdministratorAccess"

      policy_associations = {
        clusteradmin= {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type       = "cluster"
          }
        }
      }
    }
  }
  
   cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  # Extend node-to-node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # Allows Control Plane Nodes to talk to Worker nodes on all ports. Added this to simplify the example and further avoid issues with Add-ons communication with Control plane.
    # This can be restricted further to specific port based on the requirement for each Add-on e.g., metrics-server 4443, spark-operator 8080, karpenter 8443 etc.
    # Change this according to your security requirements if needed
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  # Fargate profiles use the cluster primary security group so these are not utilized
  create_cluster_security_group = false
  create_node_security_group    = false

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }

    ebs_optimized = true
    # This block device is used only for root volume. Adjust volume according to your size.
    # NOTE: Don't use this volume for Spark workloads
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
      subnet_ids = module.vpc.private_subnets
      # Smallest GPU-enabled instance
      instance_types = ["g4dn.xlarge", "g6.xlarge"]
      min_size       = 1
      max_size       = 10
      desired_size   = 1
      # Untouched AL2 Accelerated EKS Optimized Image w 30GB root storage
      ami_id = "ami-09fcc208f4f6394d4"
      ami_type = "CUSTOM"
      # Run post-creation setup processes - required for non-AL (custom) instances
      enable_bootstrap_user_data = true
      # bootstrap_extra_args = "--container-runtime nvidia-container-runtime"
    }
  }

  # We'll run all of the backgend pods on Fargate to save $$$
  # except gpu-operator, which won't run there
  fargate_profiles = {
    kube_system = {
      name = "kube-system"
      selectors = [
        { namespace = "kube-system" }
      ]
    }
  }
}
