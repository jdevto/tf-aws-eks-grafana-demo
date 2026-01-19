locals {
  default_favicon_path = "${path.module}/templates/favicon.svg"
}
resource "kubernetes_config_map" "landing_page" {
  metadata {
    name      = "landing-page-html"
    namespace = var.namespace
  }

  data = merge(
    {
      "index.html" = templatefile("${path.module}/templates/landing-page.html", {
        grafana_path_prefix = var.grafana_path_prefix
      })
    },
    {
      "favicon.svg" = var.favicon_path != null ? file("${path.module}/${var.favicon_path}") : file(local.default_favicon_path)
    }
  )
}
resource "kubernetes_deployment" "landing_page" {
  metadata {
    name      = "landing-page"
    namespace = var.namespace
    labels = {
      app = "landing-page"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "landing-page"
      }
    }

    template {
      metadata {
        labels = {
          app = "landing-page"
        }
        annotations = {
          "configmap.kubernetes.io/last-applied-configuration" = sha256(jsonencode(kubernetes_config_map.landing_page.data))
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:alpine"

          port {
            container_port = 80
          }

          volume_mount {
            name       = "html"
            mount_path = "/usr/share/nginx/html"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }
        }

        volume {
          name = "html"
          config_map {
            name = kubernetes_config_map.landing_page.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "landing_page" {
  metadata {
    name      = "landing-page"
    namespace = var.namespace
    labels = {
      app = "landing-page"
    }
  }

  spec {
    selector = {
      app = "landing-page"
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# Ingress for root path
resource "kubernetes_ingress_v1" "landing_page" {
  metadata {
    name      = "landing-page"
    namespace = var.namespace
    annotations = merge(
      {
        "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"      = "ip"
        "alb.ingress.kubernetes.io/subnets"          = join(",", var.subnet_ids)
        "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
        "alb.ingress.kubernetes.io/group.name"       = var.shared_alb_ingress_group_name
        "alb.ingress.kubernetes.io/order"            = "1"
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
          path      = "/favicon.svg"
          path_type = "Exact"
          backend {
            service {
              name = kubernetes_service.landing_page.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
        path {
          path      = "/"
          path_type = "Exact"
          backend {
            service {
              name = kubernetes_service.landing_page.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
