variable "region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-southeast-2"
}

variable "cluster_name" {
  type    = string
  default = "test"
}

variable "cluster_version" {
  type    = string
  default = "1.34"
}

variable "enable_ebs_csi_driver" {
  description = "Whether to install AWS EBS CSI Driver"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Domain name"
  type        = string
}

variable "enable_https" {
  description = "Enable HTTPS for Grafana ingress using ACM certificate"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS. Required when enable_https is true."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_shared_alb" {
  description = "Enable shared ALB functionality. When true, sets up shared ALB for multiple services to use."
  type        = bool
  default     = false
}

variable "aws_auth_map_users" {
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))
  default     = []
  description = "List of IAM users to add to aws-auth ConfigMap for Kubernetes access"
}

variable "aws_auth_map_roles" {
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  default     = []
  description = "List of IAM roles to add to aws-auth ConfigMap for Kubernetes access"
}

variable "shared_alb_allowed_ips" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "List of CIDR blocks allowed to access the shared ALB. If empty, all IPs are allowed. Example: [\"1.2.3.4/32\", \"10.0.0.0/8\"]"
}
