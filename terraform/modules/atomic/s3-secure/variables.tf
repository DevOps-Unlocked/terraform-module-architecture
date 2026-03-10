# =============================================================================
# terraform/modules/atomic/s3-secure/variables.tf
# =============================================================================

variable "bucket_name" {
  type        = string
  description = "S3 bucket name. Must be globally unique. Convention: {org}-{env}-{purpose}-{suffix}"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9\\-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 lowercase alphanumeric characters or hyphens."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "KMS CMK ARN for server-side encryption. Must be a CMK — AWS-managed keys are not accepted."
  sensitive   = true

  validation {
    condition     = can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid KMS key ARN starting with arn:aws:kms:"
  }
}

variable "data_classification" {
  type        = string
  description = "Data sensitivity level. Drives encryption tier selection and audit logging scope."

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be one of: public, internal, confidential, restricted."
  }
}

variable "cost_centre" {
  type        = string
  description = "Cost centre code for billing allocation. Required for all production resources."
}

variable "squad" {
  type        = string
  description = "Owning squad identifier. Used for incident routing and ownership tracking."
}

variable "environment" {
  type        = string
  description = "Deployment environment."

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment must be one of: prod, staging, dev."
  }
}

variable "versioning_enabled" {
  type        = bool
  description = "Enable S3 versioning. Required for HIPAA audit integrity. Disable only for scratch buckets."
  default     = true
}

variable "transition_to_ia_days" {
  type        = number
  description = "Days after creation to transition objects to Standard-IA storage class."
  default     = 90
}

variable "transition_to_glacier_days" {
  type        = number
  description = "Days after creation to transition objects to Glacier for long-term retention."
  default     = 365
}

variable "expiration_days" {
  type        = number
  description = "Days after creation to expire (delete) objects. Set to 0 to disable expiration. Default 2555 = 7 years (HIPAA minimum)."
  default     = 2555
}

variable "logging_bucket_id" {
  type        = string
  description = "S3 bucket ID to send server access logs to. Leave empty to disable logging (not recommended for prod)."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Additional tags. Mandatory compliance tags are always injected by this module and cannot be overridden."
  default     = {}
}
