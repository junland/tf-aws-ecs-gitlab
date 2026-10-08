data "aws_iam_policy_document" "ecs_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

data "aws_iam_policy_document" "host_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = local.secret_arns
  }
  dynamic "statement" {
    for_each = length(var.secret_kms_key_arns) > 0 ? [1] : []
    content {
      actions   = ["kms:Decrypt"]
      resources = var.secret_kms_key_arns
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"]
      }
    }
  }
}

resource "aws_iam_role_policy" "secrets" {
  name   = "gitlab-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.secrets.json
}

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
  tags               = local.tags
}

data "aws_iam_policy_document" "s3" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
    resources = [for bucket in local.bucket_names : "arn:${data.aws_partition.current.partition}:s3:::${bucket}"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
    resources = [for bucket in local.bucket_names : "arn:${data.aws_partition.current.partition}:s3:::${bucket}/*"]
  }
  dynamic "statement" {
    for_each = length(var.s3_kms_key_arns) > 0 ? [1] : []
    content {
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = var.s3_kms_key_arns
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"]
      }
    }
  }
}

resource "aws_iam_role_policy" "s3" {
  name   = "gitlab-object-storage"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.s3.json
}

resource "aws_iam_role" "host" {
  name               = "${var.name_prefix}-host"
  assume_role_policy = data.aws_iam_policy_document.host_trust.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "host" {
  for_each   = toset(["service-role/AmazonEC2ContainerServiceforEC2Role", "AmazonSSMManagedInstanceCore"])
  role       = aws_iam_role.host.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

resource "aws_iam_instance_profile" "host" {
  name = "${var.name_prefix}-host"
  role = aws_iam_role.host.name
  tags = local.tags
}
