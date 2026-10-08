resource "aws_s3_bucket" "gitlab" {
  for_each = var.create_s3_buckets ? local.s3_object_types : toset([])

  bucket        = var.s3_buckets == null ? null : var.s3_buckets[each.key]
  bucket_prefix = var.s3_buckets == null ? substr("${var.name_prefix}-${replace(each.key, "_", "-")}-", 0, 37) : null
  force_destroy = false
  tags          = merge(local.tags, { Name = "${var.name_prefix}-${each.key}", GitLabObjectType = each.key })
}

resource "aws_s3_bucket_public_access_block" "gitlab" {
  for_each = aws_s3_bucket.gitlab
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "gitlab" {
  for_each = aws_s3_bucket.gitlab
  bucket   = each.value.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gitlab" {
  for_each = aws_s3_bucket.gitlab
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "gitlab" {
  for_each = aws_s3_bucket.gitlab
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "gitlab" {
  for_each = aws_s3_bucket.gitlab
  bucket   = each.value.id
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  depends_on = [aws_s3_bucket_versioning.gitlab]
}

data "aws_iam_policy_document" "s3_transport" {
  for_each = aws_s3_bucket.gitlab
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value.arn, "${each.value.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "gitlab" {
  for_each   = aws_s3_bucket.gitlab
  bucket     = each.value.id
  policy     = data.aws_iam_policy_document.s3_transport[each.key].json
  depends_on = [aws_s3_bucket_public_access_block.gitlab]
}
