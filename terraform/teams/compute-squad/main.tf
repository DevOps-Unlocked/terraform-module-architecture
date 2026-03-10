# =============================================================================
# terraform/teams/compute-squad/main.tf
# DevOps Unlocked — Layer 3: Compute Squad Configuration
#
# This is what the Compute Squad actually touches.
# Pure module instantiation. No raw aws_* resources.
# No security decisions. No hardcoded infrastructure values.
#
# ALL cross-layer values (VPC, subnets, KMS ARNs) are read from SSM.
# The squad does not need to know anything about the foundation's
# backend configuration to consume its outputs.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # ACTION REQUIRED: Replace with your state bucket name
    bucket = "your-org-terraform-state-prod"
    key    = "teams/compute-squad/terraform.tfstate"
    # ACTION REQUIRED: Replace with your region
    region  = "eu-west-1"
    encrypt = true
    # ACTION REQUIRED: Replace with your KMS CMK ARN for state encryption
    kms_key_id     = "arn:aws:kms:eu-west-1:123456789012:key/mrk-REPLACE-ME"
    dynamodb_table = "terraform-state-locks"
  }
}

provider "aws" {
  # ACTION REQUIRED: Replace with your region
  region = "eu-west-1"
}

# -----------------------------------------------------------------------------
# Read ALL shared values from SSM Parameter Store.
#
# This is the correct cross-layer coupling pattern.
# The squad reads from the /platform/foundation/* contract —
# not from terraform_remote_state, not from hardcoded values.
#
# If the foundation team ever moves state, rotates a KMS key, or
# re-CIDRs the VPC, they update SSM. This file does not change.
# -----------------------------------------------------------------------------

data "aws_ssm_parameter" "vpc_id" {
  name = "/platform/foundation/vpc_id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/platform/foundation/private_subnet_ids"
}

# KMS ARNs read from SSM SecureString — decrypted at plan/apply time
# by the CI role's IAM permissions. Never hardcoded here.
data "aws_ssm_parameter" "default_kms_key_arn" {
  name            = "/platform/foundation/kms/default_key_arn"
  with_decryption = true
}

data "aws_ssm_parameter" "rds_kms_key_arn" {
  name            = "/platform/foundation/kms/rds_key_arn"
  with_decryption = true
}

# -----------------------------------------------------------------------------
# Compute Squad S3 buckets
# -----------------------------------------------------------------------------

module "compute_squad_artifacts" {
  source = "../../modules/atomic/s3-secure"
  # ACTION REQUIRED: Update to your private Terraform registry when available
  # version = "2.1.0"

  # ACTION REQUIRED: Replace with your bucket naming convention
  bucket_name         = "your-org-prod-compute-artifacts-v1"
  kms_key_arn         = data.aws_ssm_parameter.default_kms_key_arn.value
  data_classification = "internal"
  cost_centre         = "CC-1042" # ACTION REQUIRED: Replace with compute squad cost centre
  squad               = "compute"
  environment         = "prod"
  tags                = { purpose = "ci-cd-artifacts" }
}

module "compute_squad_logs" {
  source = "../../modules/atomic/s3-secure"
  # version = "2.1.0"

  # ACTION REQUIRED: Replace with your bucket naming convention
  bucket_name         = "your-org-prod-compute-logs-v1"
  kms_key_arn         = data.aws_ssm_parameter.default_kms_key_arn.value
  data_classification = "confidential"
  cost_centre         = "CC-1042" # ACTION REQUIRED
  squad               = "compute"
  environment         = "prod"
  expiration_days     = 2555 # 7 years — HIPAA minimum for audit logs
  tags                = { purpose = "application-logs" }
}

# -----------------------------------------------------------------------------
# Compute Squad RDS
# -----------------------------------------------------------------------------

module "compute_squad_db" {
  source = "../../modules/atomic/rds-postgres"
  # version = "1.4.2"

  identifier     = "compute-squad-prod"
  engine_version = "15.4"         # ACTION REQUIRED: Update to latest AWS-supported version
  instance_class = "db.r6g.large" # ACTION REQUIRED: Size based on your workload

  allocated_storage     = 100 # ACTION REQUIRED: Set based on expected data volume
  max_allocated_storage = 500 # ACTION REQUIRED: 3-5x initial storage

  database_name   = "compute_app_db"  # ACTION REQUIRED: Your application's database name
  master_username = "compute_dbadmin" # ACTION REQUIRED: Non-default username

  # All infrastructure values sourced from SSM — zero hardcoding
  kms_key_arn        = data.aws_ssm_parameter.rds_kms_key_arn.value
  vpc_id             = data.aws_ssm_parameter.vpc_id.value
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)

  # ACTION REQUIRED: Replace with your application tier security group ID
  allowed_security_group_ids = ["sg-REPLACE-ME"]

  data_classification = "confidential"
  cost_centre         = "CC-1042" # ACTION REQUIRED
  squad               = "compute"
  environment         = "prod"
  tags                = { service = "compute-api" }
}

# -----------------------------------------------------------------------------
# Compute Squad EKS Cluster
# -----------------------------------------------------------------------------

module "compute_squad_eks" {
  source = "../../modules/atomic/eks-compliant"
  # version = "1.0.0"

  cluster_name       = "compute-squad-prod"
  kubernetes_version = "1.30" # ACTION REQUIRED: Update to latest AWS-supported version

  # All infrastructure values from SSM
  kms_key_arn        = data.aws_ssm_parameter.default_kms_key_arn.value
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
  vpc_id             = data.aws_ssm_parameter.vpc_id.value

  data_classification = "confidential"
  cost_centre         = "CC-1042" # ACTION REQUIRED
  squad               = "compute"
  environment         = "prod"
  tags                = { service = "compute-platform" }
}
