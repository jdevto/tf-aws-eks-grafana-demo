variable "namespace" {
  type    = string
  default = "grafana"
}

variable "chart_version" {
  type        = string
  default     = "0.1.2"
  description = "Version of the k8sforge/grafana-chart Helm chart"
}

variable "aws_region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for ALB (should be public subnets for internet-facing ALB)"
}

variable "enable_https" {
  type        = bool
  default     = false
  description = "Enable HTTPS for Grafana ingress using ACM certificate. If true, requires certificate_arn."
}

variable "ssl_redirect" {
  type        = bool
  default     = true
  description = "Redirect HTTP to HTTPS when enable_https is true. If false, both HTTP and HTTPS are accessible."
}

variable "certificate_arn" {
  type        = string
  default     = ""
  description = "ACM certificate ARN for HTTPS. Required when enable_https is true."
}

variable "shared_alb_ingress_group_name" {
  type        = string
  default     = "shared-alb"
  description = "Name of the ingress group for shared ALB. All ingresses with this group name will share the same ALB."
}

variable "domain_name" {
  type        = string
  description = "Domain name for Grafana (e.g., dev.geonet.cloud). Used to construct the full URL."
}

variable "shared_alb_security_group_id" {
  type        = string
  default     = ""
  description = "Security group ID for shared ALB with IP restrictions. Empty if IP restrictions are not configured."
}

variable "grafana_path_prefix" {
  type        = string
  default     = "/grafana"
  description = "Path prefix for Grafana (e.g., /grafana). Used for ingress paths and health checks."
}
