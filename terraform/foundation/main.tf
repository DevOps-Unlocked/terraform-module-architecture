# =============================================================================
# terraform/foundation/main.tf
# DevOps Unlocked — Foundation Layer
#
# Owns: VPC, CloudTrail, and shared infrastructure.
# This layer is managed exclusively by the Platform team.
# Changes here have org-wide blast radius — CAB approval required.
#
# State: s3://your-state-bucket/foundation/terraform.tfstate
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
    key    = "foundation/terraform.tfstate"
    # ACTION REQUIRED: Replace with your primary AWS region
    region         = "eu-west-1"
    encrypt        = true
    # ACTION REQUIRED: Replace with your KMS CMK ARN for state encryption
    kms_key_id     = "arn:aws:kms:eu-west-1:123456789012:key/mrk-REPLACE-ME"
    dynamodb_table = "terraform-state-locks"
  }
}

provider "aws" {
  region = var.aws_region

  # Default tags applied to every resource in the foundation layer.
  # Individual resources add their own tags on top of these.
  default_tags {
    tags = {
      managed_by       = "terraform"
      layer            = "foundation"
      compliance_scope = var.compliance_scope
      environment      = var.environment
    }
  }
}

# -----------------------------------------------------------------------------
# VPC
# Single shared VPC for this AWS account.
# All team workloads deploy into private subnets.
# Public subnets exist for ALBs only — no compute, no databases.
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  # ACTION REQUIRED: Replace with your IPAM-assigned CIDR range
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.environment}-main-vpc" }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # Hard rule: private subnets never auto-assign public IPs.
  map_public_ip_on_launch = false

  tags = {
    Name                              = "${var.environment}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                     = "${var.environment}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-igw" }
}

resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"
  tags   = { Name = "${var.environment}-nat-eip-${count.index}" }
}

resource "aws_nat_gateway" "main" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.environment}-nat-${count.index}" }
}

# -----------------------------------------------------------------------------
# CloudTrail — org-wide audit logging
# Immutable audit trail. Cannot be disabled by individual squads.
# SOC 2: CC7.2 | HIPAA: §164.312(b) | ISO 27001: A.12.4
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail" {
  # ACTION REQUIRED: Replace with a globally unique name for your org
  bucket = "${var.environment}-cloudtrail-logs-${var.foundation_account_id}"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name                = "cloudtrail-audit-logs"
    data_classification = "restricted"
    retention_years     = "7"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      # ACTION REQUIRED: Replace with your KMS CMK ARN
      kms_master_key_id = var.default_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.environment}-org-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  # ACTION REQUIRED: Replace with your CloudTrail KMS CMK ARN
  kms_key_id = var.default_kms_key_arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }

  tags = { Name = "${var.environment}-org-cloudtrail" }
}
