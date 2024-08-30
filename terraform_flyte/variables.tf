
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

variable "eks_vpc_name" {
  type = string
  default = "batch-eks-vpc"
  description = "Name for the VPC supporting Batch on EKS"
}

variable "eks_vpc_cidr" {
  description = "VPC CIDR for Batch on EKS"
  type        = string
  default     = "10.1.0.0/16"
}

# Only two Subnets for with low IP range for internet access
variable "eks_public_subnets" {
  description = "Public Subnets CIDRs. 62 IPs per Subnet"
  type        = list(string)
  default     = ["10.1.255.128/26", "10.1.255.192/26"]
}

variable "eks_private_subnets" {
  description = "Private Subnets CIDRs. 32766 Subnet1 and 16382 Subnet2 IPs per Subnet"
  type        = list(string)
  default     = ["10.1.0.0/17", "10.1.128.0/18"]
}


/****************
* EKS Variables *
*****************/

variable "cluster_name" {
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

/******************
* Batch Variables *
*******************/

variable "batch_cpuOnly_min_vcpus" {
  description = "The minumum aggregate vCPU for AWS Batch CPU-Only compute environment"
  type        = number
  default     = 0
}

variable "batch_cpuOnly_max_vcpus" {
  description = "The minumum aggregate vCPU for AWS Batch CPU-Only compute environment"
  type        = number
  default     = 2048
}

variable "batch_cpuOnly_instance_types" {
  description = "The set of instance types to launch for cpu-only jobs"
  type        = list(string)
  default     = ["optimal"]
}

variable "batch_gpu_min_vcpus" {
  description = "The minimum aggregate vCPU for AWS Batch GPU compute environment"
  type        = number
  default     = 0
}

variable "batch_gpu_max_vcpus" {
  description = "The minumum aggregate vCPU for AWS Batch GPU compute environment"
  type        = number
  default     = 2048
}

variable "batch_gpu_instance_types" {
  description = "The set of instance types to launch for GPU jobs"
  type        = list(string)
  default     = ["g3s.xlarge", "g3.8xlarge", "g3.16xlarge",
                 "g4dn.xlarge", "g4dn.12xlarge", "g4dn.metal",
                 "g5.xlarge", "g5.12xlarge", "g5.24xlarge", "g5.48xlarge",
                 "g6.xlarge", "g6.12xlarge", "g6.24xlarge", "g6.48xlarge",
                 "p2", "p3", "p4d"]
}


/*********************************
* GPU Operator Variables *
**********************************/
variable "gpu_operator_version" {
  default = "24.6.0"
  description = "Version of the GPU Operator plugin"
}

variable "gpu_operator_namespace" {
  default = "gpu-operator"
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
  default = ["g3s.xlarge"]
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

/*****************************************
* Control - CPU-only Node Pool Variables *
******************************************/

variable "eksControl_cpuOnly_instance_types" {
  type        = string
  default     = "t2.medium"
  description = "CPU EC2 worker node instance type"
}

variable "eksControl_max_cpuOnly_nodes" {
  type        = string
  default     = "2"
  description = "Maximum number of CPU nodes in the Autoscaling Group"
}

variable "eksControl_min_cpuOnly_nodes" {
  type        = string
  default     = "0"
  description = "Minimum number of CPU nodes in the Autoscaling Group"
}

variable "eksControl_desired_cpuOnly_nodes" {
  type        = string
  default     = "1"
  description = "Minimum number of CPU nodes in the Autoscaling Group"
}
