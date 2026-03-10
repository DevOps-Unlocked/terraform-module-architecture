# =============================================================================
# terraform/modules/atomic/rds-postgres/outputs.tf
# =============================================================================

output "db_instance_id" {
  description = "The RDS instance identifier."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "The ARN of the RDS instance."
  value       = aws_db_instance.this.arn
}

output "db_endpoint" {
  description = "The connection endpoint (host:port). Use in application configuration."
  value       = aws_db_instance.this.endpoint
  sensitive   = true
}

output "db_name" {
  description = "The database name."
  value       = aws_db_instance.this.db_name
}

output "security_group_id" {
  description = "The RDS security group ID. Reference in application security group egress rules."
  value       = aws_security_group.rds.id
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the master user password."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
  sensitive   = true
}
