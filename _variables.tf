variable "name_prefix" {
  description = "Lowercase prefix for AWS resource names."
  type        = string
  default     = "gitlab"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,23}[a-z0-9]$", var.name_prefix)) && !strcontains(var.name_prefix, "--")
    error_message = "name_prefix must be 2-25 lowercase alphanumeric/hyphen characters, starting with a letter and ending with an alphanumeric character, without consecutive hyphens."
  }
}

variable "tags" {
  description = "Additional tags applied to AWS resources."
  type        = map(string)
  default     = {}
}

variable "create_vpc" {
  description = "Create a VPC with two public/private subnets and a shared NAT gateway."
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "IPv4 VPC CIDR. Subnets use eight additional prefix bits."
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && try(tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 20, false)
    error_message = "vpc_cidr must be an IPv4 CIDR with a /16 through /20 prefix, leaving AWS-valid /24 through /28 subnets."
  }
}

variable "azs" {
  description = "Two distinct availability zones; null selects the first two available zones in the provider region."
  type        = list(string)
  default     = null
  validation {
    condition     = var.azs == null ? true : length(var.azs) == 2 && length(distinct(var.azs)) == 2
    error_message = "azs must contain exactly two distinct availability zones."
  }
}

variable "vpc_id" {
  description = "Existing VPC ID when create_vpc is false."
  type        = string
  default     = null
}

variable "private_subnet_ids" {
  description = "At least two existing private subnets in distinct AZs. The host and data volume reside in the first subnet's AZ."
  type        = list(string)
  default     = []
}

variable "public_subnet_ids" {
  description = "At least two existing public subnets for an internet-facing load balancer."
  type        = list(string)
  default     = []
}

variable "load_balancer_internal" {
  description = "Use an internal NLB in private subnets instead of an internet-facing NLB."
  type        = bool
  default     = false
}

variable "gitlab_hostname" {
  description = "GitLab FQDN, without a scheme or path."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\\.[a-zA-Z]{2,}$", var.gitlab_hostname))
    error_message = "gitlab_hostname must be a DNS hostname, without a scheme, port, or path."
  }
}

variable "certificate_arn" {
  description = "ACM certificate ARN covering gitlab_hostname, in the provider region."
  type        = string
  validation {
    condition     = can(regex("^arn:[^:]+:acm:[^:]+:[0-9]{12}:certificate/.+$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "route53_zone_id" {
  description = "Optional Route53 hosted zone ID for a GitLab alias record. Otherwise create DNS externally."
  type        = string
  default     = null
}

variable "gitlab_ingress_cidrs" {
  description = "IPv4 CIDRs permitted to connect to HTTPS."
  type        = set(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition     = alltrue([for cidr in var.gitlab_ingress_cidrs : can(cidrnetmask(cidr))])
    error_message = "gitlab_ingress_cidrs must contain valid IPv4 CIDRs."
  }
}

variable "gitlab_ssh_cidrs" {
  description = "IPv4 CIDRs permitted to use Git-over-SSH on port 22. Empty disables external SSH access."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for cidr in var.gitlab_ssh_cidrs : can(cidrnetmask(cidr))])
    error_message = "gitlab_ssh_cidrs must contain valid IPv4 CIDRs."
  }
}

variable "gitlab_image" {
  description = "Pinned x86_64 GitLab Linux-package Docker image (CE or EE). Supply an explicit version tag or digest; latest is rejected."
  type        = string
  validation {
    condition     = can(regex("(:[^/:]+|@sha256:[a-f0-9]{64})$", var.gitlab_image)) && !endswith(var.gitlab_image, ":latest")
    error_message = "gitlab_image must have an explicit version tag or SHA256 digest, not latest."
  }
}

variable "instance_type" {
  description = "x86_64 EC2 instance type. Leave memory for the OS and ECS agent beyond gitlab_memory."
  type        = string
  default     = "m6i.xlarge"
}

variable "ami_id" {
  description = "Optional ECS-optimized x86_64 Amazon Linux 2023 AMI. Null uses the AWS SSM recommended image."
  type        = string
  default     = null
}

variable "gitlab_cpu" {
  description = "ECS CPU units reserved by GitLab (1024 units per vCPU)."
  type        = number
  default     = 3072
  validation {
    condition     = var.gitlab_cpu >= 1024 && floor(var.gitlab_cpu) == var.gitlab_cpu
    error_message = "gitlab_cpu must be an integer of at least 1024."
  }
}

variable "gitlab_memory" {
  description = "Container hard memory limit in MiB."
  type        = number
  default     = 12288
  validation {
    condition     = var.gitlab_memory >= 8192 && floor(var.gitlab_memory) == var.gitlab_memory
    error_message = "gitlab_memory must be an integer of at least 8192 MiB."
  }
}

variable "data_volume_size" {
  description = "Persistent encrypted gp3 data volume size in GiB. Growth requires an OS filesystem resize."
  type        = number
  default     = 100
  validation {
    condition     = var.data_volume_size >= 20 && var.data_volume_size <= 16384 && floor(var.data_volume_size) == var.data_volume_size
    error_message = "data_volume_size must be an integer between 20 and 16384 GiB."
  }
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key for EBS and Redis encryption."
  type        = string
  default     = null
}

variable "postgresql_port" {
  description = "RDS PostgreSQL port."
  type        = number
  default     = 5432
  validation {
    condition     = var.postgresql_port >= 1 && var.postgresql_port <= 65535 && floor(var.postgresql_port) == var.postgresql_port
    error_message = "postgresql_port must be an integer from 1 to 65535."
  }
}

variable "postgresql_database" {
  description = "GitLab database name created by RDS."
  type        = string
  default     = "gitlabhq_production"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.postgresql_database))
    error_message = "postgresql_database must start with a letter and contain only letters, digits, and underscores (maximum 63 characters)."
  }
}

variable "postgresql_username" {
  description = "RDS master username used by GitLab."
  type        = string
  default     = "gitlab"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,15}$", var.postgresql_username))
    error_message = "postgresql_username must start with a letter and contain only letters, digits, and underscores (maximum 16 characters)."
  }
}

variable "postgresql_engine_version" {
  description = "RDS PostgreSQL version supported by the selected GitLab image."
  type        = string
  default     = "16"
}

variable "postgresql_instance_class" {
  description = "RDS PostgreSQL instance class."
  type        = string
  default     = "db.t4g.medium"
}

variable "postgresql_allocated_storage" {
  description = "Initial RDS gp3 storage in GiB."
  type        = number
  default     = 100
  validation {
    condition     = var.postgresql_allocated_storage >= 20 && var.postgresql_allocated_storage <= 1000 && floor(var.postgresql_allocated_storage) == var.postgresql_allocated_storage
    error_message = "postgresql_allocated_storage must be an integer from 20 to 1000 GiB."
  }
}

variable "postgresql_multi_az" {
  description = "Enable RDS Multi-AZ standby."
  type        = bool
  default     = true
}

variable "postgresql_deletion_protection" {
  description = "Protect RDS against deletion. Disable explicitly only after backing up GitLab."
  type        = bool
  default     = true
}

variable "postgresql_final_snapshot_identifier" {
  description = "Unique final snapshot identifier when deleting RDS; null uses name_prefix-postgresql-final."
  type        = string
  default     = null
}

variable "gitlab_root_password_secret_arn" {
  description = "Secrets Manager ARN containing the initial root password as a raw string. Used only on first boot."
  type        = string
  validation {
    condition     = can(regex("^arn:[^:]+:secretsmanager:[^:]+:[0-9]{12}:secret:.+$", var.gitlab_root_password_secret_arn))
    error_message = "gitlab_root_password_secret_arn must be a Secrets Manager secret ARN."
  }
}

variable "secret_kms_key_arns" {
  description = "Customer-managed KMS key ARNs the execution role may use to decrypt the initial root password secret."
  type        = set(string)
  default     = []
}

variable "elasticache_node_type" {
  description = "ElastiCache Redis node type."
  type        = string
  default     = "cache.t4g.small"
}

variable "elasticache_engine_version" {
  description = "Redis OSS engine version supported by both ElastiCache and the selected GitLab image."
  type        = string
  default     = "7.1"
}

variable "s3_buckets" {
  description = "Required existing S3 buckets for consolidated GitLab object storage. All eight object types must be supplied."
  nullable    = false
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
  validation {
    condition     = alltrue([for bucket in values(var.s3_buckets) : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", bucket))])
    error_message = "s3_buckets must contain nonempty S3 bucket names for every object type."
  }
}

variable "s3_kms_key_arns" {
  description = "Optional customer-managed KMS key ARNs for the configured S3 buckets."
  type        = set(string)
  default     = []
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 30
}
