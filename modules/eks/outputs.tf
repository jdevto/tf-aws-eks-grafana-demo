output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_ca_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "aws_lb_controller_role_arn" {
  value       = aws_iam_role.aws_lb_controller.arn
  description = "IAM role ARN for AWS Load Balancer Controller"
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.eks.arn
  description = "ARN of the EKS OIDC provider"
}

output "ebs_csi_driver_role_arn" {
  value       = var.enable_ebs_csi_driver ? aws_iam_role.ebs_csi_driver[0].arn : null
  description = "IAM role ARN for EBS CSI Driver"
}

output "enable_shared_alb" {
  value       = var.enable_shared_alb
  description = "Whether shared ALB functionality is enabled"
}

output "shared_alb_dns_name" {
  value = length(data.aws_lb.shared_alb_details) > 0 ? try(
    data.aws_lb.shared_alb_details[0].dns_name,
    ""
  ) : ""
  description = "Shared ALB DNS name (used by multiple services via ingress group name). Empty until ALB is created by AWS Load Balancer Controller or if enable_shared_alb is false."
}

output "shared_alb_zone_id" {
  value = length(data.aws_lb.shared_alb_details) > 0 ? try(
    data.aws_lb.shared_alb_details[0].zone_id,
    ""
  ) : ""
  description = "Shared ALB zone ID (used by multiple services via ingress group name). Empty until ALB is created by AWS Load Balancer Controller or if enable_shared_alb is false."
}

output "shared_alb_ingress_group_name" {
  value       = var.enable_shared_alb ? var.shared_alb_ingress_group_name : ""
  description = "Name of the ingress group for shared ALB. Empty if enable_shared_alb is false."
}

output "shared_alb_security_group_id" {
  value       = var.enable_shared_alb && length(var.shared_alb_allowed_ips) > 0 ? aws_security_group.shared_alb[0].id : ""
  description = "Security group ID for shared ALB with IP restrictions. Empty if IP restrictions are not configured."
}
