module "vpc" {
  source = "./modules/vpc"

  name               = var.cluster_name
  cluster_name       = var.cluster_name
  availability_zones = ["${var.region}a", "${var.region}b"]

  tags = merge(local.common_tags, {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

module "eks" {
  source = "./modules/eks"

  cluster_name                  = local.cluster_name
  cluster_version               = var.cluster_version
  enable_ebs_csi_driver         = var.enable_ebs_csi_driver
  enable_shared_alb             = var.enable_shared_alb
  shared_alb_ingress_group_name = var.enable_shared_alb ? "platform" : ""
  subnet_ids                    = concat(module.vpc.private_subnet_ids, module.vpc.public_subnet_ids)
  node_subnet_ids               = module.vpc.private_subnet_ids
  vpc_id                        = module.vpc.vpc_id
  tags                          = local.common_tags
  aws_auth_map_users            = var.aws_auth_map_users
  aws_auth_map_roles            = var.aws_auth_map_roles
  shared_alb_allowed_ips        = var.shared_alb_allowed_ips

  depends_on = [module.vpc]
}

module "route53_platform" {
  source = "./modules/route53"

  count = var.enable_shared_alb ? 1 : 0

  name         = "platform"
  domain_name  = var.domain_name
  alb_dns_name = module.eks.shared_alb_dns_name
  alb_zone_id  = module.eks.shared_alb_zone_id
}

module "landing_page" {
  source = "./modules/landing-page"

  count = var.enable_shared_alb ? 1 : 0

  subnet_ids                    = module.vpc.public_subnet_ids
  shared_alb_ingress_group_name = module.eks.shared_alb_ingress_group_name
  shared_alb_security_group_id  = module.eks.shared_alb_security_group_id
  enable_https                  = var.enable_https
  certificate_arn               = var.enable_https ? var.certificate_arn : ""
  ssl_redirect                  = var.enable_https
  grafana_path_prefix           = "/grafana"

  depends_on = [
    module.eks,
    module.vpc
  ]
}

module "grafana" {
  source = "./modules/grafana"

  aws_region                    = var.region
  cluster_name                  = module.eks.cluster_name
  subnet_ids                    = module.vpc.public_subnet_ids
  enable_https                  = var.enable_https
  certificate_arn               = var.certificate_arn
  ssl_redirect                  = var.enable_https
  shared_alb_ingress_group_name = module.eks.shared_alb_ingress_group_name
  shared_alb_security_group_id  = module.eks.shared_alb_security_group_id
  domain_name                   = var.domain_name

  depends_on = [
    module.eks,
    module.vpc
  ]
}
