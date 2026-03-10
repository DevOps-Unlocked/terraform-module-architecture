# =============================================================================
# terraform/foundation/ssm.tf
#
# Publishes ALL foundation outputs to SSM Parameter Store.
# This is the single coupling mechanism between layers.
#
# WHY SSM instead of terraform_remote_state?
# - terraform_remote_state creates a hard dependency on the backend config.
#   If the foundation team moves state, every consumer breaks.
# - SSM is a stable contract: /platform/foundation/* is the interface.
# - IAM can grant ssm:GetParameter on the path without exposing the state bucket.
# - CloudTrail logs every parameter read — clean audit trail of who consumed what.
#
# All cross-layer values — including KMS ARNs — are published here.
# No team config should hardcode a value that originates in the foundation.
# =============================================================================

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "vpc_id" {
  name        = "/platform/foundation/vpc_id"
  type        = "String"
  value       = aws_vpc.main.id
  description = "Shared production VPC ID."
  tags        = { published_by = "foundation" }
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name        = "/platform/foundation/private_subnet_ids"
  type        = "StringList"
  value       = join(",", aws_subnet.private[*].id)
  description = "Private subnet IDs (comma-separated). Use for all compute workloads."
  tags        = { published_by = "foundation" }
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name        = "/platform/foundation/public_subnet_ids"
  type        = "StringList"
  value       = join(",", aws_subnet.public[*].id)
  description = "Public subnet IDs (comma-separated). ALBs only — never compute."
  tags        = { published_by = "foundation" }
}

resource "aws_ssm_parameter" "availability_zones" {
  name        = "/platform/foundation/availability_zones"
  type        = "StringList"
  value       = join(",", var.availability_zones)
  description = "Availability zones used by the foundation layer."
  tags        = { published_by = "foundation" }
}

# -----------------------------------------------------------------------------
# KMS Keys
# Published as SecureString so values are encrypted at rest in SSM.
# Only roles with kms:Decrypt on the SSM key can read the plaintext ARN.
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "default_kms_key_arn" {
  name        = "/platform/foundation/kms/default_key_arn"
  type        = "SecureString"
  value       = var.default_kms_key_arn
  description = "Default KMS CMK ARN for general resource encryption (S3, EBS, SSM)."
  tags        = { published_by = "foundation" }
}

resource "aws_ssm_parameter" "rds_kms_key_arn" {
  name        = "/platform/foundation/kms/rds_key_arn"
  type        = "SecureString"
  value       = var.rds_kms_key_arn
  description = "KMS CMK ARN for RDS encryption. Separate key for audit isolation."
  tags        = { published_by = "foundation" }
}

resource "aws_ssm_parameter" "eks_secrets_kms_key_arn" {
  name        = "/platform/foundation/kms/eks_secrets_key_arn"
  type        = "SecureString"
  value       = var.eks_secrets_kms_key_arn
  description = "KMS CMK ARN for Kubernetes Secrets envelope encryption."
  tags        = { published_by = "foundation" }
}
