resource "helm_release" "grafana" {
  name             = "grafana"
  namespace        = var.namespace
  create_namespace = true
  repository       = "https://k8sforge.github.io/grafana-chart"
  chart            = "grafana"
  version          = var.chart_version

  wait      = true
  skip_crds = true

  values = [
    yamlencode({
      replicaCount = 1
      ingress = {
        enabled = false
      }
      resources = {
        server = {
          requests = {
            memory = "256Mi"
            cpu    = "100m"
          }
          limits = {
            memory = "512Mi"
            cpu    = "500m"
          }
        }
      }
      grafana = {
        enabled = true
        service = {
          type       = "ClusterIP"
          port       = 80
          targetPort = 3000
        }
        ingress = {
          enabled = false
        }
        persistence = {
          enabled = true
          type    = "pvc"
          size    = "10Gi"
        }
        adminUser     = "admin"
        adminPassword = "admin"
        "grafana.ini" = {
          server = {
            root_url            = var.enable_https ? "https://${var.domain_name}${var.grafana_path_prefix}" : "http://${var.domain_name}${var.grafana_path_prefix}"
            serve_from_sub_path = true
          }
        }
      }
    })
  ]
}

resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = var.namespace
    annotations = merge(
      {
        "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"              = "ip"
        "alb.ingress.kubernetes.io/subnets"                  = join(",", var.subnet_ids)
        "alb.ingress.kubernetes.io/backend-protocol"         = "HTTP"
        "alb.ingress.kubernetes.io/healthcheck-path"         = "${var.grafana_path_prefix}/api/health"
        "alb.ingress.kubernetes.io/group.name"               = var.shared_alb_ingress_group_name
        "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=3600"
      },
      var.shared_alb_security_group_id != "" ? {
        "alb.ingress.kubernetes.io/security-groups" = var.shared_alb_security_group_id
      } : {},
      !var.enable_https ? {
        "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 80}]"
      } : {},
      var.enable_https ? {
        "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
        "alb.ingress.kubernetes.io/certificate-arn" = var.certificate_arn
        "alb.ingress.kubernetes.io/ssl-policy"      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      } : {},
      var.enable_https && var.ssl_redirect ? {
        "alb.ingress.kubernetes.io/ssl-redirect" = "443"
      } : {}
    )
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "${var.grafana_path_prefix}/api/health"
          path_type = "Exact"
          backend {
            service {
              name = "grafana"
              port {
                number = 80
              }
            }
          }
        }
        path {
          path      = var.grafana_path_prefix
          path_type = "Prefix"
          backend {
            service {
              name = "grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.grafana]
}

data "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana"
    namespace = var.namespace
  }

  depends_on = [helm_release.grafana]
}

data "kubernetes_ingress_v1" "grafana_server" {
  metadata {
    name      = "grafana"
    namespace = var.namespace
  }

  depends_on = [kubernetes_ingress_v1.grafana]
}
