
/****************
* AWS Variables *
*****************/

variable "region" {
  description = "AWS region to provision the EKS cluster"
  default     = "us-east-2"
  type        = string
}

variable "ssh_key" {
  type    = string
  default = ""
}

/****************
* VPC Variables *
*****************/

variable "vpc_cidr" {
  description = "VPC CIDR for Batch on EKS"
  type        = string
  default     = "10.1.0.0/16"
}

# Routable Public subnets with NAT Gateway and Internet Gateway. Not required for fully private clusters
variable "public_subnets" {
  description = "Public Subnets CIDRs. 62 IPs per Subnet/AZ"
  default     = ["10.1.0.0/26", "10.1.0.64/26"]
  type        = list(string)
}

# Routable Private subnets only for Private NAT Gateway -> Transit Gateway -> Second VPC for overlapping overlapping CIDRs
variable "private_subnets" {
  description = "Private Subnets CIDRs. 254 IPs per Subnet/AZ for Private NAT + NLB + Airflow + EC2 Jumphost etc."
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
  type        = list(string)
}

# RFC6598 range 100.64.0.0/10
# Note you can only /16 range to VPC. You can add multiples of /16 if required
variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  default     = ["100.64.0.0/16"]
  type        = list(string)
}

# EKS Worker nodes and pods will be placed on these subnets. Each Private subnet can get 32766 IPs.
# RFC6598 range 100.64.0.0/10
variable "eks_data_plane_subnet_secondary_cidr" {
  description = "Secondary CIDR blocks. 32766 IPs per Subnet per Subnet/AZ for EKS Node and Pods"
  default     = ["100.64.0.0/17", "100.64.128.0/17"]
  type        = list(string)
}

/****************
* EKS Variables *
*****************/

variable "name" {
  default = "cloudpipe"
  type    = string
}

variable "kubernetes_version" {
  description = "Version of EKS to install on the control plane (Major and Minor version only, do not include the patch)"
  type        = string
  default     = "1.31"
}
variable "additional_user_data" {
  type        = string
  default     = ""
  description = "User data that is appended to the user data script after of the EKS bootstrap script."
}

/*************************
* GPU Operator Variables *
**************************/
variable "gpu_operator_version" {
  default     = "24.9.0"
  description = "Version of the GPU Operator plugin"
}

variable "gpu_operator_namespace" {
  default     = "gpu-operator"
  description = "K8s namespace of the GPU Operator plugin"
}

###############################
# Managed Node Pool Variables #
###############################

variable "eksControl_gpu_nodePool_instance_types" {
  type        = list(string)
  default     = ["g3s.xlarge"]
  description = "GPU EC2 worker node instance type"
}

variable "eksControl_max_gpu_nodes" {
  type        = string
  default     = "1"
  description = "Maximum number of GPU nodes in the Autoscaling Group"
}

variable "eksControl_min_gpu_nodes" {
  type        = string
  default     = "1"
  description = "Minimum number of GPU nodes in the Autoscaling Group"
}

variable "eksControl_desired_gpu_nodes" {
  type        = string
  default     = "1"
  description = "Minimum number of GPU nodes in the Autoscaling Group"
}

############################
# Argo Workflows Variables #
############################

variable "argo_workflows_namespace" {
  type    = string
  default = "argo-workflows"
}

variable "argo_workflows_serverIRSA_name" {
  type    = string
  default = "argo-workflows-server"
}

variable "argo_workflows_controllerIRSA_name" {
  type    = string
  default = "argo-workflows-controller"
}

variable "argo_workflows_bucket" {
  type    = string
  default = "brave-abcd"
}

variable "argo_workflows_s3accessIRSA_name" {
  type    = string
  default = "argo-workflows-s3access"
}

variable "argo_workflows_db_name" {
  type        = string
  description = "Database name"
  default     = "argoworkflows"
}

variable "argo_workflows_db_username" {
  type        = string
  description = "Database admin account username"
  default     = "admin"
}

# variable "db_password" {
#   type        = string
#   description = "Database admin account password"
# }

variable "argo_workflows_db_class" {
  type        = string
  description = "Database instance type"
  default     = "db.m5.large"
}

variable "argo_workflows_db_allocated_storage" {
  type        = string
  description = "The size of the database (Gb)"
  default     = "20"
}

variable "argo_workflows_db_secret_name" {
  type        = string
  description = "The name of the secret to store the database credentials"
  default     = "argo-workflows-db-secret"
}

variable "argo_workflows_db_table_name" {
  type        = string
  description = "The name of the database table to create for Argo Workflows"
  default     = "argo_workflows"
}

variable "argo_events_namespace" {
  type    = string
  default = "argo-events"
}

#######################
# Karpenter Variables #
#######################

variable "karpenter_namespace" {
  type    = string
  default = "karpenter"
}

#######################
# SQS Queue Variables #
#######################



variable "grafana_region" {
  type    = string
  default = "us"
}



variable "operator_chart_version" {
  description = "The chart version of opentelemetry-operator to use"
  type        = string
  # renovate-helm: depName=opentelemetry-operator registryUrl=https://open-telemetry.github.io/opentelemetry-helm-charts
  default = "0.68.1"
}
