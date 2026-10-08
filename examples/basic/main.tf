terraform {
  required_version = ">= 1.13.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.68, < 7.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "gitlab" {
  source = "../.."

  name_prefix                     = "gitlab"
  gitlab_hostname                 = var.gitlab_hostname
  gitlab_image                    = var.gitlab_image
  bottlerocket_bootstrap_image    = var.bottlerocket_bootstrap_image
  certificate_arn                 = var.certificate_arn
  gitlab_root_password_secret_arn = var.gitlab_root_password_secret_arn
  route53_zone_id                 = var.route53_zone_id
  gitlab_ingress_cidrs            = var.gitlab_ingress_cidrs
  gitlab_ssh_cidrs                = var.gitlab_ssh_cidrs
  s3_buckets                      = var.s3_buckets
  create_s3_buckets               = var.create_s3_buckets

  tags = {
    Environment = "production"
    Workload    = "gitlab"
  }
}

variable "aws_region" {
  description = "AWS region for all resources, including the certificate and S3 buckets."
  type        = string
  default     = "us-east-1"
}

variable "gitlab_hostname" {
  description = "GitLab DNS hostname."
  type        = string
}

variable "gitlab_image" {
  description = "Supported pinned official GitLab CE or EE Docker image."
  type        = string
}

variable "bottlerocket_bootstrap_image" {
  description = "Optional pinned official Bottlerocket bootstrap image override; null uses the AMI default."
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the GitLab hostname."
  type        = string
}

variable "gitlab_root_password_secret_arn" {
  description = "Secrets Manager ARN containing a strong initial root password as a raw string."
  type        = string
}

variable "route53_zone_id" {
  description = "Optional Route53 hosted zone ID."
  type        = string
  default     = null
}

variable "gitlab_ingress_cidrs" {
  description = "IPv4 networks allowed to access GitLab HTTPS."
  type        = set(string)
}

variable "gitlab_ssh_cidrs" {
  description = "IPv4 networks allowed to access Git-over-SSH."
  type        = set(string)
  default     = []
}

variable "s3_buckets" {
  description = "Optional explicit names for all eight buckets; null creates uniquely named managed buckets."
  default     = null
  type = object({
    artifacts        = string
    uploads          = string
    packages         = string
    lfs              = string
    terraform_state  = string
    dependency_proxy = string
    ci_secure_files  = string
    external_diffs   = string
  })
}

variable "create_s3_buckets" {
  description = "Create/configure buckets by default; set false with s3_buckets to use existing buckets."
  type        = bool
  default     = true
}

output "gitlab_url" {
  description = "GitLab HTTPS URL."
  value       = module.gitlab.gitlab_url
}

output "load_balancer_dns_name" {
  description = "NLB target for external DNS."
  value       = module.gitlab.load_balancer_dns_name
}
