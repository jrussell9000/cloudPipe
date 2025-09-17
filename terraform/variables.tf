
/****************
* AWS Variables *
*****************/

variable "region" {
  default = "us-east-2"
  type    = string
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


# RFC6598 range 100.64.0.0/10
# Note you can only /16 range to VPC. You can add multiples of /16 if required
variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  default     = ["100.64.0.0/16"]
  type        = list(string)
}


# # Routable Public subnets with NAT Gateway and Internet Gateway. Not required for fully private clusters
# variable "public_subnets" {
#   description = "Public Subnets CIDRs. 62 IPs per Subnet/AZ"
#   default     = ["10.1.0.0/26", "10.1.0.64/26"]
#   type        = list(string)
# }

# # Routable Private subnets only for Private NAT Gateway -> Transit Gateway -> Second VPC for overlapping overlapping CIDRs
# variable "private_subnets" {
#   description = "Private Subnets CIDRs. 254 IPs per Subnet/AZ for Private NAT + NLB + Airflow + EC2 Jumphost etc."
#   default     = ["10.1.1.0/24", "10.1.2.0/24"]
#   type        = list(string)
# }

# # RFC6598 range 100.64.0.0/10
# # Note you can only /16 range to VPC. You can add multiples of /16 if required
# variable "secondary_cidr_blocks" {
#   description = "Secondary CIDR blocks to be attached to VPC"
#   default     = ["100.64.0.0/16"]
#   type        = list(string)
# }

# # EKS Worker nodes and pods will be placed on these subnets. Each Private subnet can get 32766 IPs.
# # RFC6598 range 100.64.0.0/10
# variable "eks_data_plane_subnet_secondary_cidr" {
#   description = "Secondary CIDR blocks. 32766 IPs per Subnet per Subnet/AZ for EKS Node and Pods"
#   default     = ["100.64.0.0/17", "100.64.128.0/17"]
#   type        = list(string)
# }

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
  default     = "1.33"
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

############################
# Argo Workflows Variables #
############################

variable "argo_workflows_namespace" {
  type    = string
  default = "argo-workflows"
}

variable "argo_workflows_server_IRSA_name" {
  type    = string
  default = "argo-workflows-server"
}

variable "argo_workflows_controller_IRSA_name" {
  type    = string
  default = "argo-workflows-controller"
}

variable "argo_workflows_bucket" {
  type    = string
  default = "abcd-working"
}

variable "argo_workflows_runner_IRSA_name" {
  type    = string
  default = "argo-workflows-runner"
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

variable "argo_workflows_workflow2trigger" {
  type        = string
  description = "The name of the Argo Workflows workflow or workflowtemplate to be triggered by Argo Events."
  default     = "cloudpipe-long-master-workflow-template"
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

variable "argo_events_handler_sa" {
  type    = string
  default = "argo-events-handler-sa"
}

variable "grafana_region" {
  type    = string
  default = "us"
}

variable "operator_chart_version" {
  description = "The chart version of opentelemetry-operator to use"
  type        = string
  # renovate-helm: depName=opentelemetry-operator registryUrl=https://open-telemetry.github.io/opentelemetry-helm-charts
  default = "0.84.0"
}


variable "monitoring_namespace" {
  description = "Namespace for monitoring services"
  type        = string
  default     = "monitoring"
}


variable "grafana_admin_sso_ids" {
  description = "List of AWS SSO User or Group IDs to assign Grafana Admin role. Required if using AWS_SSO authentication."
  type        = list(string)
  default     = ["01dbd590-e041-7037-85a4-31646453ee0a", "e1dbe5a0-d0b1-700d-3fe5-815968958634"]
}


variable "idp_metadata_url" {
  description = "Link to the identity provider metadata. Retrieved from IAM>Identity Providers>AWSSSO_YYY_DO_NOT_DELETE"
  type        = string
  default     = "https://signin.aws.amazon.com/static/saml/SAMLSPAKKH6NNLV8CBP36Z/saml-metadata.xml"
}

variable "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group to create/use for EKS logs."
  type        = string
  default     = "/aws/eks/fluentbit-logs/logs" # Example structure
}

variable "log_retention_days" {
  description = "Number of days to retain logs in CloudWatch."
  type        = number
  default     = 7 # Adjust as needed
}

variable "fluent_bit_namespace" {
  description = "Kubernetes namespace to deploy Fluent Bit into."
  type        = string
  default     = "amazon-cloudwatch"
}

variable "fluent_bit_service_account_name" {
  description = "Name of the Kubernetes Service Account for Fluent Bit."
  type        = string
  default     = "fluent-bit"
}

variable "fluent_bit_image" {
  description = "Fluent Bit container image to use (AWS optimized version recommended)."
  type        = string
  default     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:latest" # Use a specific version in production
}
