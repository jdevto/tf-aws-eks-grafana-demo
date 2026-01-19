data "aws_region" "current" {}

data "aws_vpc" "this" {
  id = var.vpc_id
}
data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.cluster_name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
data "aws_iam_policy_document" "eks_nodes_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_nodes" {
  name               = "${var.cluster_name}-eks-nodes-role"
  assume_role_policy = data.aws_iam_policy_document.eks_nodes_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_nodes_worker" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_nodes_cni" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_nodes_ecr" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# EKS control plane
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = true
    public_access_cidrs     = var.public_access_cidrs
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]
}

# Managed node group
resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-default"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.node_subnet_ids != null ? var.node_subnet_ids : var.subnet_ids

  instance_types = var.node_instance_types

  disk_size = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = var.node_update_max_unavailable
  }

  dynamic "remote_access" {
    for_each = var.node_remote_access_enabled ? [1] : []
    content {
      ec2_ssh_key               = var.node_remote_access_ssh_key
      source_security_group_ids = var.node_remote_access_security_groups
    }
  }

  labels = var.node_labels

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes_worker,
    aws_iam_role_policy_attachment.eks_nodes_cni,
    aws_iam_role_policy_attachment.eks_nodes_ecr,
  ]
}

locals {
  node_group_role = {
    rolearn  = aws_iam_role.eks_nodes.arn
    username = "system:node:{{EC2PrivateDNSName}}"
    groups = [
      "system:bootstrappers",
      "system:nodes"
    ]
  }

  all_map_roles = concat([local.node_group_role], var.aws_auth_map_roles)
}

resource "kubernetes_config_map_v1_data" "aws_auth" {
  count = length(var.aws_auth_map_users) > 0 || length(var.aws_auth_map_roles) > 0 || true ? 1 : 0

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  force = true

  data = {
    mapUsers = length(var.aws_auth_map_users) > 0 ? yamlencode(var.aws_auth_map_users) : yamlencode([])
    mapRoles = yamlencode(local.all_map_roles)
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.default
  ]

  lifecycle {
    ignore_changes = all
  }
}

# =============================================================================
# EBS CSI Driver IAM (IRSA setup)
# =============================================================================

# IAM role for EBS CSI Driver
data "aws_iam_policy_document" "ebs_csi_driver_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role.json
  tags               = var.tags
}

# Custom least-privilege IAM policy for EBS CSI Driver
resource "aws_iam_role_policy" "ebs_csi_driver" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  name = "${var.cluster_name}-ebs-csi-driver-policy"
  role = aws_iam_role.ebs_csi_driver[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EBSCSIVolumeManagement"
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume",
          "ec2:DeleteVolume",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:ModifyVolume"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.region
          }
        }
      },
      {
        Sid    = "EBSCSISnapshotManagement"
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.region
          }
        }
      },
      {
        Sid    = "EBSCSIDescribeOperations"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
      {
        Sid    = "EBSCSITaggingOperations"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DescribeTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = [
              "CreateVolume",
              "CreateSnapshot"
            ]
          }
        }
      }
    ]
  })
}

# EBS CSI Driver Add-on
resource "aws_eks_addon" "ebs_csi_driver" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs_csi_driver_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.ebs_csi_driver[0].arn

  depends_on = [
    aws_eks_node_group.default,
    aws_iam_role_policy.ebs_csi_driver[0]
  ]

  tags = var.tags
}

# Default StorageClass for EBS CSI Driver
resource "kubernetes_storage_class" "ebs_csi_default" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }

  depends_on = [
    aws_eks_addon.ebs_csi_driver[0]
  ]
}

# =============================================================================
# AWS Load Balancer Controller IAM (IRSA setup)
# Note: Kubernetes resources are created at root level to avoid provider cycles
# =============================================================================

# OIDC provider for IRSA
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = var.tags
}

# IAM role for AWS Load Balancer Controller
data "aws_iam_policy_document" "aws_lb_controller_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "aws_lb_controller" {
  name               = "${var.cluster_name}-aws-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.aws_lb_controller_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "aws_lb_controller" {
  role       = aws_iam_role.aws_lb_controller.name
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
}

resource "aws_iam_role_policy_attachment" "aws_lb_controller_ec2" {
  role       = aws_iam_role.aws_lb_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy" "aws_lb_controller_waf" {
  name = "${var.cluster_name}-aws-lb-controller-waf"
  role = aws_iam_role.aws_lb_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WAFv2Permissions"
        Effect = "Allow"
        Action = [
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "wafv2:ListWebACLs"
        ]
        Resource = "*"
      },
      {
        Sid    = "WAFRegionalPermissions"
        Effect = "Allow"
        Action = [
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "waf-regional:ListWebACLs"
        ]
        Resource = "*"
      },
      {
        Sid    = "ShieldPermissions"
        Effect = "Allow"
        Action = [
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# AWS Load Balancer Controller Installation
# =============================================================================

# Kubernetes Service Account for AWS Load Balancer Controller
resource "kubernetes_service_account" "aws_lb_controller" {
  count = var.enable_aws_lb_controller ? 1 : 0

  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_lb_controller.arn
    }
    labels = {
      "app.kubernetes.io/name"       = "aws-load-balancer-controller"
      "app.kubernetes.io/component"  = "controller"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.default,
    aws_iam_role_policy_attachment.aws_lb_controller,
    aws_iam_role_policy_attachment.aws_lb_controller_ec2,
    aws_iam_role_policy.aws_lb_controller_waf
  ]
}

# Helm Release for AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  count = var.enable_aws_lb_controller ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.aws_lb_controller_helm_version

  set {
    name  = "clusterName"
    value = aws_eks_cluster.this.name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "region"
    value = data.aws_region.current.region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  dynamic "set" {
    for_each = var.aws_lb_controller_helm_values
    content {
      name  = set.key
      value = set.value
    }
  }

  depends_on = [
    kubernetes_service_account.aws_lb_controller[0],
    aws_eks_node_group.default
  ]
}

data "aws_lbs" "shared_alb" {
  count = var.enable_shared_alb && var.shared_alb_ingress_group_name != "" ? 1 : 0

  tags = {
    "elbv2.k8s.aws/cluster" = aws_eks_cluster.this.name
    "ingress.k8s.aws/stack" = var.shared_alb_ingress_group_name
  }

  depends_on = [
    helm_release.aws_load_balancer_controller
  ]
}

locals {
  shared_alb_arns_list = var.enable_shared_alb && var.shared_alb_ingress_group_name != "" && length(data.aws_lbs.shared_alb) > 0 ? try(
    tolist(data.aws_lbs.shared_alb[0].arns),
    []
  ) : []
  shared_alb_arn = length(local.shared_alb_arns_list) > 0 ? local.shared_alb_arns_list[0] : ""

  shared_alb_allowed_cidrs = var.enable_shared_alb && length(var.shared_alb_allowed_ips) > 0 ? distinct(concat(
    [data.aws_vpc.this.cidr_block],
    var.shared_alb_allowed_ips
  )) : []
}

data "aws_lb" "shared_alb_details" {
  count = var.enable_shared_alb && var.shared_alb_ingress_group_name != "" && local.shared_alb_arn != "" ? 1 : 0
  arn   = local.shared_alb_arn
}

resource "aws_security_group" "shared_alb" {
  count = var.enable_shared_alb && length(var.shared_alb_allowed_ips) > 0 ? 1 : 0

  name        = "${var.cluster_name}-shared-alb"
  description = "Security group for shared ALB with IP restrictions"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-shared-alb"
    }
  )
}
resource "aws_security_group_rule" "shared_alb_http_ingress" {
  count = var.enable_shared_alb && length(var.shared_alb_allowed_ips) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = local.shared_alb_allowed_cidrs
  security_group_id = aws_security_group.shared_alb[0].id
  description       = "Allow HTTP from VPC CIDR and allowed IPs"
}
resource "aws_security_group_rule" "shared_alb_https_ingress" {
  count = var.enable_shared_alb && length(var.shared_alb_allowed_ips) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = local.shared_alb_allowed_cidrs
  security_group_id = aws_security_group.shared_alb[0].id
  description       = "Allow HTTPS from VPC CIDR and allowed IPs"
}
resource "aws_security_group_rule" "shared_alb_egress" {
  count = var.enable_shared_alb && length(var.shared_alb_allowed_ips) > 0 ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.shared_alb[0].id
  description       = "Allow all outbound traffic"
}
data "aws_security_groups" "node_security_groups" {
  count = var.enable_shared_alb && length(var.shared_alb_allowed_ips) > 0 ? 1 : 0

  filter {
    name   = "tag:kubernetes.io/cluster/${var.cluster_name}"
    values = ["owned"]
  }

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  depends_on = [aws_eks_node_group.default]
}

resource "aws_security_group_rule" "node_from_alb" {
  count = var.enable_shared_alb && length(var.shared_alb_allowed_ips) > 0 && length(data.aws_security_groups.node_security_groups) > 0 && length(try(data.aws_security_groups.node_security_groups[0].ids, [])) > 0 ? length(data.aws_security_groups.node_security_groups[0].ids) : 0

  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.shared_alb[0].id
  security_group_id        = data.aws_security_groups.node_security_groups[0].ids[count.index]
  description              = "Allow traffic from shared ALB security group to nodes"
}
