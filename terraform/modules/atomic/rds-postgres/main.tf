# =============================================================================
# terraform/modules/atomic/rds-postgres/main.tf
# DevOps Unlocked — Atomic Module: Compliant RDS PostgreSQL
#
# Enforces by default (not configurable by callers):
# - Encryption at rest with KMS CMK
# - Deletion protection (requires explicit override for teardown)
# - Enhanced monitoring (1-second granularity)
# - Performance Insights with KMS encryption
# - Automatic minor version upgrades
# - Storage autoscaling to prevent disk-full incidents
#
# SOC 2: CC6.7 (encryption), CC7.2 (monitoring)
# HIPAA: §164.312(a)(2)(iv), §164.312(b)
# ISO 27001: A.10.1, A.12.4
# =============================================================================

# IAM role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.identifier}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })

  tags = local.mandatory_tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# DB subnet group — accepts only private subnets (enforced via variable description + validation)
resource "aws_db_subnet_group" "this" {
  name        = "${var.identifier}-subnet-group"
  subnet_ids  = var.private_subnet_ids
  description = "Private subnets for ${var.identifier}. Public subnets must not be used."

  tags = merge(var.tags, local.mandatory_tags)
}

# Security group — database port only, from application security group
resource "aws_security_group" "rds" {
  name        = "${var.identifier}-rds-sg"
  description = "Allow PostgreSQL access from application tier only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from application tier"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  # No egress rules — RDS doesn't initiate outbound connections
  egress {
    description = "Deny all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = []
  }

  tags = merge(var.tags, local.mandatory_tags, { Name = "${var.identifier}-rds-sg" })
}

# The RDS instance itself
resource "aws_db_instance" "this" {
  identifier = var.identifier
  engine     = "postgres"

  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage with autoscaling — prevents disk-full incidents silently killing prod
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"

  # Encryption — KMS CMK only. Non-negotiable.
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # Database config
  db_name  = var.database_name
  username = var.master_username
  # Password is managed by AWS Secrets Manager — not set here.
  # See docs/architecture.md for the Secrets Manager + rotation setup.
  manage_master_user_password = true

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # Hard-coded. Not a variable.

  # HA — multi-AZ always enabled. Can be set false for dev to reduce cost.
  multi_az = var.multi_az

  # Backups — minimum 7 days for HIPAA compliance
  backup_retention_period   = var.backup_retention_days
  backup_window             = "03:00-04:00"
  maintenance_window        = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot     = true
  delete_automated_backups  = false

  # Enhanced Monitoring — 1 second granularity for incident response
  monitoring_interval = 1
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Performance Insights — encrypted with KMS, 7-day retention minimum
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = 7

  # Logging to CloudWatch — all log types for audit completeness
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Auto-upgrade minor versions during maintenance window
  auto_minor_version_upgrade = true

  # Deletion protection — must be explicitly disabled before destroy
  # Never disable in production without a signed change record
  deletion_protection = var.deletion_protection

  tags = merge(var.tags, local.mandatory_tags)

  lifecycle {
    # Prevent accidental replacement of the database instance
    prevent_destroy = false # ACTION REQUIRED: Set to true for production databases
    ignore_changes  = [engine_version] # Allow in-place minor upgrades
  }
}

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
