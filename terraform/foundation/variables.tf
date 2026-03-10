# =============================================================================
# terraform/foundation/variables.tf
# =============================================================================

variable "aws_region" {
  type        = string
  description = "AWS region for the foundation layer."
  # ACTION REQUIRED: Replace with your primary region
  default = "eu-west-1"
}

variable "foundation_account_id" {
  type        = string
  description = "AWS Account ID for the platform/foundation account. Used for globally unique resource naming."
  # ACTION REQUIRED: Replace with your account ID
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the shared VPC. Coordinate with your IPAM team before changing."
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block (e.g., 10.0.0.0/16)."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets. Must be within vpc_cidr. One per AZ."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets (ALB only). Must be within vpc_cidr. One per AZ."
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones to deploy subnets into. Length must match subnet CIDR lists."
}

variable "default_kms_key_arn" {
  type        = string
  description = "ARN of the default KMS CMK for encrypting resources in this account."
  sensitive   = true
  # ACTION REQUIRED: Must be a pre-created CMK — not the AWS-managed default key
}

variable "environment" {
  type        = string
  description = "Environment name. Controls tagging, log retention tiers, and encryption key selection."
  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment must be one of: prod, staging, dev."
  }
}

variable "compliance_scope" {
  type        = string
  description = "Compliance frameworks in scope. Applied as a tag to all resources."
  default     = "soc2-hipaa"
}

variable "rds_kms_key_arn" {
  type        = string
  description = "KMS CMK ARN for RDS encryption. Can match default_kms_key_arn or be a separate key for audit isolation."
  sensitive   = true
}

variable "eks_secrets_kms_key_arn" {
  type        = string
  description = "KMS CMK ARN for Kubernetes Secrets envelope encryption in EKS clusters."
  sensitive   = true
}
