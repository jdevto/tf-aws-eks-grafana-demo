# tf-aws-eks-grafana-demo

Grafana on EKS with Terraform automation demo

This repository demonstrates deploying Grafana on AWS EKS using Terraform, with a shared Application Load Balancer (ALB) for ingress.

## Features

- **EKS Cluster**: Managed Kubernetes cluster on AWS
- **Grafana**: Deployed using [k8sforge/grafana-chart](https://k8sforge.github.io/grafana-chart/) wrapper chart
- **Shared ALB**: Single ALB for multiple services
- **Route53 Integration**: DNS records for platform domain
- **Landing Page**: Simple landing page with service links

## Architecture

- VPC with public and private subnets
- EKS cluster in private subnets
- Shared ALB in public subnets
- Grafana accessible via `/grafana` path prefix
- Route53 DNS for custom domain

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.6.0
- kubectl configured for EKS access
- Domain name with Route53 hosted zone
- ACM certificate (if using HTTPS)

## Quick Start

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and update values:

   ```hcl
   domain_name       = "your-domain.com"
   enable_https      = true
   certificate_arn   = "arn:aws:acm:region:account:certificate/..."
   enable_shared_alb = true
   ```

2. Initialize Terraform:

   ```bash
   terraform init
   ```

3. Plan and apply:

   ```bash
   terraform plan
   terraform apply
   ```

## Access Grafana

After deployment, get the Grafana URL and credentials:

```bash
# Get Grafana URL
terraform output grafana_server_url

# Get Grafana password
terraform output grafana_password
```

Default username: `admin`

Grafana will be accessible at: `https://your-domain.com/grafana`

## Module Structure

- `modules/vpc/` - VPC and networking
- `modules/eks/` - EKS cluster and node groups
- `modules/grafana/` - Grafana Helm deployment
- `modules/route53/` - DNS records
- `modules/landing-page/` - Landing page service

## Outputs

- `grafana_server_url` - Grafana server URL
- `grafana_username` - Grafana admin username
- `grafana_password` - Grafana admin password
- `platform_url` - Platform base URL
- `shared_alb_dns_name` - Shared ALB DNS name

## Configuration

### Grafana Chart

This demo uses the [k8sforge/grafana-chart](https://k8sforge.github.io/grafana-chart/) wrapper chart (version 0.1.2), which provides:

- Sensible defaults for resource limits
- High availability support
- OIDC/OAuth configuration support
- ServiceMonitor for Prometheus

### Security Groups

When `shared_alb_allowed_ips` is configured, the module creates a security group that:

- Allows HTTP/HTTPS from VPC CIDR and specified IPs
- Allows all outbound traffic for health checks
- Allows traffic from ALB security group to node security groups

## Notes

- This is a minimal configuration for demonstration purposes
- Uses SQLite database (single instance)
- OIDC/Cognito authentication can be added later
- Database configuration (PostgreSQL) can be added for HA
- See [k8sforge/grafana-chart](https://github.com/k8sforge/grafana-chart) for advanced configuration options
