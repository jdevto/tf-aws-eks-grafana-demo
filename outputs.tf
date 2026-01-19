output "grafana_server_url" {
  description = "Grafana server URL"
  value       = module.grafana.grafana_server_url
}

output "grafana_username" {
  description = "Grafana username"
  value       = module.grafana.grafana_username
}

output "grafana_password" {
  description = "Grafana password"
  value       = module.grafana.grafana_password
}

output "platform_url" {
  description = "Platform URL with protocol (http:// or https://)"
  value = var.enable_shared_alb ? (
    var.enable_https ? "https://${module.route53_platform[0].custom_domain}" : "http://${module.route53_platform[0].custom_domain}"
  ) : ""
}

output "shared_alb_dns_name" {
  description = "Shared ALB DNS name"
  value       = module.eks.shared_alb_dns_name
}
