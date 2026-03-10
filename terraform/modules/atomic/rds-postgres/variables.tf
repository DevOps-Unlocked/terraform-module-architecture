# =============================================================================
# terraform/modules/atomic/rds-postgres/variables.tf
# =============================================================================

variable "identifier" {
  type        = string
  description = "Unique identifier for the RDS instance. Used as prefix for all associated resources."
}

variable "engine_version" {
  type        = string
  description = "PostgreSQL engine version. Must be within N-1 of current AWS-supported latest."
}

variable "instance_class" {
  type        = string
  description = "RDS instance class. Use db.t3.medium for dev, db.r6g.large+ for production workloads."
}

variable "allocated_storage" {
  type        = number
  description = "Initial allocated storage in GB."
}

variable "max_allocated_storage" {
  type        = number
  description = "Maximum storage in GB for autoscaling. Set to 3-5x initial storage."
}

variable "database_name" {
  type        = string
  description = "Name of the initial database to create."
}

variable "master_username" {
  type        = string
  description = "Master DB username. Do not use 'admin', 'root', or 'postgres'."

  validation {
    condition     = !contains(["admin", "root", "postgres", "administrator"], var.master_username)
    error_message = "master_username must not be a common default username (admin, root, postgres, administrator)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "KMS CMK ARN for storage and Performance Insights encryption."
  sensitive   = true

  validation {
    condition     = can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid KMS ARN."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to deploy the RDS instance into. Sourced from foundation SSM output."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the DB subnet group. Must be private — public subnets are not supported."
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to connect on port 5432 (application tier only)."
}

variable "multi_az" {
  type        = bool
  description = "Enable Multi-AZ deployment. Always true in production. May be false in dev to reduce cost."
  default     = true
}

variable "backup_retention_days" {
  type        = number
  description = "Automated backup retention in days. Minimum 7 for SOC 2 / HIPAA compliance."
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 7
    error_message = "backup_retention_days must be at least 7 days for HIPAA compliance."
  }
}

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection. Must be disabled (and change documented) before terraform destroy."
  default     = true
}

variable "data_classification" {
  type        = string
  description = "Data sensitivity level."

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be one of: public, internal, confidential, restricted."
  }
}

variable "cost_centre" {
  type        = string
  description = "Cost centre code for billing allocation."
}

variable "squad" {
  type        = string
  description = "Owning squad identifier."
}

variable "environment" {
  type        = string
  description = "Deployment environment."

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment must be one of: prod, staging, dev."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags. Mandatory compliance tags cannot be overridden."
  default     = {}
}
