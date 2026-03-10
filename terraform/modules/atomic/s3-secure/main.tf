# =============================================================================
# terraform/modules/atomic/s3-secure/main.tf
# DevOps Unlocked — Atomic Module: Compliant S3 Bucket
#
# This module creates an S3 bucket that is:
# - Encrypted at rest with a KMS CMK (not SSE-S3 / AES256)
# - Completely blocked from public access (all four settings)
# - Versioned for audit integrity
# - Access-logged to a designated logging bucket
# - Tagged with mandatory compliance metadata
#
# What callers CANNOT do via this module:
# - Create a public bucket
# - Skip encryption
# - Use SSE-S3 instead of KMS
# - Omit mandatory compliance tags
#
# SOC 2: CC6.7 (encryption), CC6.6 (public access)
# HIPAA: §164.312(a)(2)(iv) (encryption), §164.312(e)(2)(ii)
# ISO 27001: A.10.1 (cryptographic controls)
# =============================================================================

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  # Merge caller-supplied tags with mandatory compliance tags.
  # Mandatory tags always win — callers cannot override them.
  tags = merge(var.tags, local.mandatory_tags)

  lifecycle {
    # Prevent accidental deletion of buckets containing data.
    # Override this only for scratch/transient buckets in dev.
    prevent_destroy = false # ACTION REQUIRED: Set to true for production data buckets
  }
}

# Block all public access. Hard-coded. Not a variable. Not negotiable.
# SOC 2 CC6.6: Prevent logical access from unauthorized principals.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# KMS CMK encryption. We explicitly do not support SSE-S3 (AES256).
# SSE-S3 does not provide key management, rotation audit trails, or
# the ability to revoke access by disabling the key.
# For HIPAA and SOC 2, CMK is the correct choice.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    # Bucket key reduces KMS API call costs by ~99% for high-throughput buckets
    bucket_key_enabled = true
  }
}

# Versioning: required for HIPAA audit integrity and SOC 2 change tracking.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Lifecycle rules: transition to IA, then Glacier, then expire.
# Defaults enforce 7-year retention for HIPAA audit logs.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "compliance-lifecycle"
    status = "Enabled"

    transition {
      days          = var.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.transition_to_glacier_days
      storage_class = "GLACIER"
    }

    dynamic "expiration" {
      for_each = var.expiration_days > 0 ? [1] : []
      content {
        days = var.expiration_days
      }
    }
  }
}

# Server access logging. Every GET/PUT/DELETE is logged.
# Required for SOC 2 CC7.2 and HIPAA §164.312(b) audit trail.
resource "aws_s3_bucket_logging" "this" {
  count = var.logging_bucket_id != "" ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.logging_bucket_id
  target_prefix = "s3-access-logs/${var.bucket_name}/"
}

# -----------------------------------------------------------------------------
# Mandatory tags: injected by this module regardless of caller input.
# These tags are required for SOC 2 CC6.1 and cost allocation.
# -----------------------------------------------------------------------------
locals {
  mandatory_tags = {
    managed_by          = "terraform"
    compliance_scope    = "soc2-hipaa"
    data_classification = var.data_classification
    cost_centre         = var.cost_centre
    squad               = var.squad
    environment         = var.environment
  }
}
