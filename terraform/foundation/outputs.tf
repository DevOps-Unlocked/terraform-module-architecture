# =============================================================================
# terraform/foundation/outputs.tf
#
# Expose only what downstream layers need. Nothing more.
# These outputs are consumed via SSM Parameter Store (preferred) or
# terraform_remote_state data sources in the service module layer.
# =============================================================================

output "vpc_id" {
  description = "The shared production VPC ID."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs across all AZs. Use for all compute workloads."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs. Use for ALBs only — never for compute or databases."
  value       = aws_subnet.public[*].id
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs — one per AZ for HA egress."
  value       = aws_nat_gateway.main[*].id
}

output "cloudtrail_bucket_arn" {
  description = "ARN of the CloudTrail audit log bucket. Used in IAM policies for log access."
  value       = aws_s3_bucket.cloudtrail.arn
}

output "availability_zones" {
  description = "AZs used by the foundation layer. Reference in modules to ensure subnet alignment."
  value       = var.availability_zones
}
