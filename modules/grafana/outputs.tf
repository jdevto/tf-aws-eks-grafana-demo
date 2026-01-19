output "grafana_namespace" {
  value = var.namespace
}

output "grafana_server_service_name" {
  value = "grafana"
}

output "grafana_username" {
  value       = "admin"
  description = "Grafana admin username"
}

output "grafana_password" {
  value = try(
    base64decode(data.kubernetes_secret.grafana_admin.data["admin-password"]),
    "Password not available yet. Run: kubectl get secret -n grafana grafana -o jsonpath='{.data.admin-password}' | base64 -d"
  )
  sensitive   = false
  description = "Grafana admin password"
}

output "grafana_server_url" {
  value = coalesce(
    try(
      length(data.kubernetes_ingress_v1.grafana_server.status[0].load_balancer[0].ingress) > 0 ? (
        try(
          "${var.enable_https ? "https" : "http"}://${data.kubernetes_ingress_v1.grafana_server.status[0].load_balancer[0].ingress[0].hostname}${var.grafana_path_prefix}",
          "${var.enable_https ? "https" : "http"}://${data.kubernetes_ingress_v1.grafana_server.status[0].load_balancer[0].ingress[0].ip}${var.grafana_path_prefix}"
        )
      ) : null,
      null
    ),
    "ALB URL not in Ingress status yet. Run: aws elbv2 describe-load-balancers --region ${var.aws_region} --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-${var.shared_alb_ingress_group_name}`)].DNSName' --output text"
  )
  description = "Grafana server ALB URL. If showing a command, Ingress status is not populated yet."
}
