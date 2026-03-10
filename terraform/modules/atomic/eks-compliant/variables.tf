# =============================================================================
# terraform/modules/atomic/eks-compliant/variables.tf
# =============================================================================

variable "cluster_name" {
  type        = string
  description = "EKS cluster name."
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version."
  validation {
    condition     = can(regex("^1\.(2[6-9]|3[0-9])$", var.kubernetes_version))
    error_message = "Kubernetes version must be 1.26 or later."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs."
}

variable "security_group_ids" {
  type        = list(string)
  description = "Additional security groups for the cluster."
  default     = []
}

variable "kms_key_arn" {
  type        = string
  description = "KMS ARN for secrets encryption."
  sensitive   = true
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
  description = "Cost centre code."
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
  description = "Additional tags."
  default     = {}
}
