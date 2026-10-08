# Terraform AWS ECS GitLab Module

Run the GitLab Linux-package Docker image on Amazon ECS with **required RDS PostgreSQL, ElastiCache Redis, and S3 object storage**. Modeled after [tf-aws-eks-gitlab](https://github.com/junland/tf-aws-eks-gitlab), this module uses native AWS resources, responsibility-based `_*.tf` files, managed/existing networking, scoped IAM, and native Terraform tests.

## Architecture

- One **Bottlerocket `aws-ecs-2` x86_64 EC2 host**, in a private subnet, running one GitLab CE/EE container.
- A separate encrypted gp3 EBS volume persists `/etc/gitlab`, `/var/log/gitlab`, and `/var/opt/gitlab`. An essential Bottlerocket bootstrap container mounts it at host `/mnt/gitlab` before ECS starts, on every boot. Replacements reuse the volume in the same availability zone. Separate encrypted root/runtime disks are disposable.
- A Network Load Balancer terminates HTTPS using ACM on port 443 and forwards to host port 8080. Git-over-SSH uses NLB port 22 and host port 2222. There is no public host administration port or HTTP listener.
- Private encrypted **RDS PostgreSQL**, Multi-AZ by default, with seven-day backups and an RDS-managed Secrets Manager password.
- Private **ElastiCache Redis OSS**, with encryption at rest/in transit, seven-day snapshots, and access restricted to the host security group. Redis is single-node and relies on network isolation, not password authentication.
- **Managed S3 buckets by default** for artifacts, uploads, packages, LFS, Terraform state, dependency proxy, CI secure files, and external diffs. All eight buckets have encryption, versioning, public-access blocking, disabled ACLs, TLS-only policies, and incomplete multipart-upload cleanup. The task role accesses only these buckets; no static AWS credentials are used.
- CloudWatch container logs, separate execution/application/host roles, mandatory IMDSv2, blocked container access to the host instance profile, and Systems Manager for administration.

This is a **single-node GitLab deployment**, not a horizontally scalable or highly available GitLab cluster. Updates stop the old task before starting its replacement, preventing concurrent writes to repository storage but causing downtime. RDS Multi-AZ does not make the GitLab host or Redis highly available.

ECS on EC2 is intentional: GitLab needs shared memory and local block storage for Gitaly. [GitLab does not support NFS for repository storage](https://docs.gitlab.com/administration/gitaly/); EFS is therefore not used. Fargate is not supported by this module.

## Requirements

- Terraform >= 1.13; HashiCorp AWS provider >= 6.68, < 7.0.
- A supported, explicitly versioned **x86_64** official GitLab image. Match GitLab's supported PostgreSQL/Redis versions before deploying or upgrading. `latest` is rejected.
- An ACM certificate in the deployment region covering your GitLab hostname.
- Outbound access to the regional Bottlerocket bootstrap/control image registries. The AMI supplies the official bootstrap image by default; `bottlerocket_bootstrap_image` may override it with a compatible, explicitly versioned script-running image.
- A Secrets Manager secret in the deployment region containing a strong initial root password as a **raw string**, not JSON. The module never reads the secret value into Terraform state.
- S3 permissions to provision and configure the eight managed buckets. Alternatively, set `create_s3_buckets = false` and supply eight existing private buckets in the deployment region. Existing bucket security/lifecycle settings remain the owner's responsibility; bucket policies must permit the task role. For existing SSE-KMS buckets supply `s3_kms_key_arns` and suitable key policies.
- DNS resolving the GitLab hostname to the NLB. Supply `route53_zone_id` to create an alias, or manage an alias/CNAME externally.
- AWS permissions to provision these resources, pass IAM roles, and create the ECS service-linked role if it does not exist.

The module **always creates RDS and ElastiCache** and always configures S3, creating buckets by default; bundled PostgreSQL and Redis are disabled. Existing database/cache endpoints are not accepted. The container registry, Prometheus stack, and GitLab Runner are not deployed.

## Usage

Configure the AWS provider in the calling root module; this child module inherits its region and credentials.

```hcl
provider "aws" {
  region = "us-east-1"
}

module "gitlab" {
  source = "github.com/junland/tf-aws-ecs-gitlab?ref=<reviewed-commit-or-tag>"

  gitlab_hostname                 = "gitlab.example.com"
  gitlab_image                    = var.gitlab_image
  certificate_arn                 = var.certificate_arn
  gitlab_root_password_secret_arn = var.gitlab_root_password_secret_arn
  route53_zone_id                 = var.route53_zone_id
  gitlab_ingress_cidrs            = ["203.0.113.0/24"]
  gitlab_ssh_cidrs                = ["203.0.113.0/24"]

  tags = { Environment = "production" }
}
```

The runnable caller configuration is in `examples/basic/main.tf`. Supply its required inputs through your normal Terraform variable mechanism, then run:

```sh
terraform -chdir=examples/basic init
terraform -chdir=examples/basic plan
terraform -chdir=examples/basic apply
```

No passwords belong in `.tf` files or committed variable files. ARN references, rather than password values, enter the task definition. GitLab will write its runtime configuration and encryption secrets to the persistent volume; protect volume snapshots and access accordingly.

### Existing networking

Set `create_vpc = false` and provide `vpc_id`, at least two `private_subnet_ids` in distinct availability zones, and at least two `public_subnet_ids` for the internet-facing NLB. Set `load_balancer_internal = true` to use private subnets instead and omit public subnet IDs.

All supplied subnets must belong to the supplied VPC. Existing private subnets need outbound connectivity for image pulls, SSM, CloudWatch, Secrets Manager, S3, and GitLab integrations, through NAT or the appropriate endpoints/proxy. The managed VPC creates two public/private subnet pairs and one shared NAT gateway. Public subnets require internet-gateway routes for an internet-facing NLB.

The **first private subnet determines the host/data-volume AZ**. Changing that AZ attempts to replace the protected data volume and is intentionally blocked. Migrate data explicitly rather than treating an AZ change as an ordinary redeploy.

### S3 ownership and migration

Omit `s3_buckets` to create eight uniquely named buckets using `name_prefix`, the object type, and a provider-generated suffix. Names are available in the `s3_buckets` output and automatically reach GitLab and its scoped task-role policy. Set all eight explicit names to create buckets with chosen globally available names.

Managed buckets use SSE-S3 (`AES256`), versioning, BucketOwnerEnforced ownership (no ACLs), all four public-access blocks, and a policy denying non-TLS requests. Lifecycle rules abort incomplete multipart uploads after seven days but do **not** expire current objects or previous versions. Monitor storage costs and configure retention deliberately; versioning is not a complete backup. Nonempty buckets cannot be destroyed because `force_destroy` is false.

To preserve existing installations, **set `create_s3_buckets = false` before upgrading** and retain your current `s3_buckets` map. Merely supplying existing names with the new default does not import buckets: Terraform will attempt to create them. Existing-bucket mode requires all eight names and never changes their configuration. If transferring ownership to this module, first import each bucket and its configuration resources at the `_s3.tf` addresses, then review the plan carefully; do not switch modes or change names without a data migration.

The required `s3_buckets` object for existing-bucket mode contains `artifacts`, `uploads`, `packages`, `lfs`, `terraform_state`, `dependency_proxy`, `ci_secure_files`, and `external_diffs`. Managed explicit names must be distinct.

## Inputs

Required inputs have no defaults:

| Input | Purpose |
| --- | --- |
| `gitlab_hostname` | GitLab FQDN without a scheme/path |
| `gitlab_image` | Pinned GitLab CE/EE Docker image tag or digest |
| `certificate_arn` | ACM certificate covering the hostname |
| `gitlab_root_password_secret_arn` | Initial root password secret ARN |

Important optional settings:

| Input | Default | Purpose |
| --- | --- | --- |
| `name_prefix` | `gitlab` | Lowercase resource name prefix, 2–25 characters |
| `tags` | `{}` | Additional AWS resource tags |
| `create_s3_buckets` | `true` | Create/configure all eight buckets; false uses existing buckets |
| `s3_buckets` | `null` | Optional explicit names for managed buckets; all eight required in existing-bucket mode |
| `create_vpc` | `true` | Manage networking |
| `vpc_cidr` | `10.0.0.0/16` | Managed VPC CIDR; subnets add eight prefix bits |
| `azs` | First two available AZs | Two distinct managed subnet AZs |
| `vpc_id` / `private_subnet_ids` / `public_subnet_ids` | `null` / `[]` / `[]` | Existing networking |
| `load_balancer_internal` | `false` | Private NLB |
| `gitlab_ingress_cidrs` | `["0.0.0.0/0"]` | HTTPS IPv4 allowlist; restrict for private installations |
| `gitlab_ssh_cidrs` | `[]` | Git-over-SSH IPv4 allowlist; blocked by default |
| `route53_zone_id` | `null` | Optional managed DNS alias |
| `instance_type` | `m6i.xlarge` | x86_64 host, with memory/CPU headroom beyond the container |
| `ami_id` | Latest Bottlerocket `aws-ecs-2` x86_64 AMI | Optional compatible Bottlerocket AMI override |
| `bottlerocket_bootstrap_image` | AMI's regional default | Optional pinned official script-running bootstrap image override |
| `gitlab_cpu` / `gitlab_memory` | `3072` / `12288` | CPU units / hard memory limit in MiB |
| `data_volume_size` | `100` | Persistent EBS size in GiB |
| `kms_key_arn` | `null` | Optional encryption key for EBS, RDS storage, and Redis |
| `postgresql_database` / `postgresql_username` | `gitlabhq_production` / `gitlab` | RDS database / master username |
| `postgresql_port` | `5432` | RDS port |
| `postgresql_engine_version` | `16` | RDS PostgreSQL version; match selected GitLab image |
| `postgresql_instance_class` | `db.t4g.medium` | RDS sizing |
| `postgresql_allocated_storage` | `100` | Initial RDS gp3 GiB; autoscaling ceiling 1000 GiB |
| `postgresql_multi_az` | `true` | RDS standby |
| `postgresql_deletion_protection` | `true` | Explicit protection against database deletion |
| `postgresql_final_snapshot_identifier` | `<name_prefix>-postgresql-final` | Final snapshot name; choose a unique name if reused |
| `elasticache_node_type` / `elasticache_engine_version` | `cache.t4g.small` / `7.1` | Required managed Redis sizing/version |
| `secret_kms_key_arns` | `[]` | Decryption permissions for a custom-key root secret |
| `s3_kms_key_arns` | `[]` | Decryption/data-key permissions for S3 custom keys |
| `log_retention_days` | `30` | CloudWatch log retention |

See `_variables.tf` for types and validation. Custom KMS keys must reside in the appropriate region and their key policies must authorize the relevant AWS services/roles.

## Outputs

The module exposes `s3_buckets` (effective names keyed by object type), `gitlab_url`, `gitlab_ssh_hostname`, `load_balancer_dns_name`, `load_balancer_zone_id`, ECS `cluster_name`/`cluster_arn`/`service_name`/`task_definition_arn`, `vpc_id`, subnet IDs, `host_instance_id`, `host_security_group_id`, `data_volume_id`, `task_role_arn`, `postgresql_endpoint`, `postgresql_password_secret_arn`, `elasticache_primary_endpoint`, and `log_group_name`.

The PostgreSQL secret output is an **ARN only**, never the password.

## Operations and limitations

- **Readiness:** Terraform submission is not proof of application readiness. Check ECS service/task events, CloudWatch logs, and NLB target health. Initial GitLab configuration/migrations can take several minutes; the service has a 900-second load-balancer health grace period. The monitoring allowlist admits localhost and the VPC CIDR for NLB readiness probes. Confirm the sign-in page is available over HTTPS and sign in as `root`.
- **Credentials:** ECS selects the `password` JSON field of the RDS-managed secret at task startup. Automatic database-password rotation is explicitly disabled because ECS cannot refresh a running container's environment. For a planned rotation, use RDS's managed-password rotation operation, then force a new ECS deployment so GitLab receives the new value. Expect downtime. Do not enable unattended rotation without implementing synchronized task refresh.
- **Database privileges:** GitLab uses the RDS master user to bootstrap its database, including required extensions. This account has elevated RDS privileges; restrict secret access and isolate the instance. PostgreSQL connections require TLS.
- **TLS boundary:** HTTPS terminates at the NLB; traffic from NLB to GitLab is HTTP inside the private VPC. Database and Redis connections use TLS. The GitLab NGINX configuration supplies HTTPS forwarding headers for the TLS-offload setup.
- **Persistence:** Task restarts/upgrades preserve repositories and GitLab encryption secrets. The EBS volume has `prevent_destroy = true`; ordinary `terraform destroy` is blocked. Take verified backups, deliberately remove that lifecycle protection only when decommissioning/migrating, and disable RDS deletion protection in a prior apply before destroying. RDS takes a final snapshot; existing S3 buckets are never destroyed by this module, and managed buckets require deliberate removal of all objects/versions before deletion.
- **Backups:** RDS/Redis snapshots are not complete GitLab backups. Schedule GitLab application backups and EBS snapshots, preserve `/etc/gitlab/gitlab-secrets.json`, protect S3 data, and test coordinated restores. Live block snapshots alone may not be application-consistent.
- **Storage growth:** Increasing `data_volume_size` enlarges EBS but does not resize the ext4 filesystem. Resize through an explicitly authorized Bottlerocket admin/maintenance container after expansion, then disable that container. The host root/runtime disks are disposable.
- **Host maintenance:** Use SSM through Bottlerocket's control container, not direct SSH. The admin container is disabled by default. The immutable host accepts native TOML settings, not cloud-init shell scripts; task IAM and awslogs execution-role support are built into the Bottlerocket ECS agent. Pin a compatible Bottlerocket `ami_id` for controlled replacements; the default public SSM AMI may change on a later apply. There is no Auto Scaling Group or automatic host failover.
- **Upgrades:** Follow GitLab's required upgrade stops and database compatibility guidance. Change the pinned image only after a verified backup. Never raise service desired count or allow overlapping deployments against this volume.
- **Scope:** No CI runners, container registry, SMTP, or multi-node Gitaly/Praefect are configured. Provision those separately as needed. NAT, NLB, EC2/EBS, RDS, Redis, and logs incur AWS charges.

### Migrating an existing Amazon Linux host

Back up and verify the EBS/GitLab configuration, database, and S3 data before applying this change. Clear any Amazon Linux `ami_id` override or replace it with a compatible Bottlerocket AMI. The host is replaced with downtime; the protected GitLab EBS volume is stopped/detached and reattached in the same AZ. Its ext4 filesystem and the three existing directories are reused without copying or reformatting. Only host paths change from `/srv/gitlab` to `/mnt/gitlab`; GitLab container paths stay unchanged.

`templates/user_data.toml.tftpl` registers an **essential**, `always` bootstrap container using Bottlerocket's official script executor. It runs the base64-encoded `templates/bootstrap-storage.sh.tftpl`, waits up to ten minutes for the exact EBS NVMe serial, formats only a blank unsigned disk, rejects non-ext4 filesystems, and mounts under Bottlerocket's shared-propagation `/mnt` path with a compatible SELinux context. It then installs the bridge-network IMDS firewall rule before Docker/ECS starts; task-role credentials at `169.254.170.2` remain available. No `/etc/fstab`, cloud-init, or systemd edits are used.

If the volume is not attached before the timeout, the essential bootstrap fails and ECS remains unavailable rather than starting GitLab on empty host directories. Correct the attachment or bootstrap error and reboot through EC2. Boot/reboot, filesystem writes under SELinux, IMDS blocking, and application health should be verified on the chosen AMI in a real AWS deployment; mocked Terraform tests cannot establish these runtime properties.

## Validation

```sh
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
terraform -chdir=examples/basic init -backend=false
terraform -chdir=examples/basic validate
```

`tests/basic.tftest.hcl` uses AWS **mocks** and plan-only runs: no AWS credentials, cloud resources, or paid services are needed. Tests cover managed/existing networking and S3 buckets, generated names, bucket security/lifecycle settings, private encrypted dependencies, scoped S3 IAM, Bottlerocket AMI/TOML/bootstrap settings, encrypted runtime storage, task mounts/shared memory, single-writer deployment settings, secret references, TLS/SSH, and invalid inputs. These are configuration tests, **not a live deployment or end-to-end GitLab test**.

## License

BSD 2-Clause; see `LICENSE`.
