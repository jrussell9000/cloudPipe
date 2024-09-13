
/****************
* AWS Variables *
*****************/

variable "region" {
  description = "AWS region to provision the EKS cluster"
  default     = "us-east-1"
  type        = string
}

variable "ssh_key" {
  type    = string
  default = ""
}

/****************
* VPC Variables *
*****************/

variable "vpc_name" {
  type        = string
  default     = "batch-eks-vpc"
  description = "Name for the VPC supporting Batch on EKS"
}

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

variable "cluster_name" {
  default = "batch-eks"
  type    = string
}

variable "name" {
  default = "batch-eks"
  type    = string
}

variable "cluster_version" {
  description = "Version of EKS to install on the control plane (Major and Minor version only, do not include the patch)"
  type        = string
  default     = "1.30"
}
variable "additional_user_data" {
  type        = string
  default     = ""
  description = "User data that is appended to the user data script after of the EKS bootstrap script."
}


/*********************************
* GPU Operator Variables *
**********************************/
variable "gpu_operator_version" {
  default     = "24.6.0"
  description = "Version of the GPU Operator plugin"
}

variable "gpu_operator_namespace" {
  default     = "gpu-operator"
  description = "K8s namespace of the GPU Operator plugin"
}

###############################
# Managed Node Pool Variables #
###############################

/*****************************************
* Control - GPU-only Node Pool Variables *
******************************************/
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

###############################
# Managed Node Pool Variables #
###############################

# variable "s3_bucket_name" {
#   type = string
#   default = "fastProc"
# }


variable "argowf_namespace" {
  type    = string
  default = "argo-workflows"
}

variable "argowf_server_serviceaccount" {
  type    = string
  default = "argo-workflows-server-sa"
}

variable "argowf_controller_serviceaccount" {
  type    = string
  default = "argo-workflows-controller-sa"
}
