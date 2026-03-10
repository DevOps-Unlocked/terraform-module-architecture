# =============================================================================
# terraform/modules/atomic/eks-compliant/main.tf
# DevOps Unlocked — Atomic Module: Compliant EKS Cluster
#
# Enforces by default:
# - Private API endpoint only
# - Envelope encryption of secrets via KMS CMK
# - Control plane logging enabled
# - IRSA enabled
# - Mandatory tagging for cost and compliance
# =============================================================================

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = local.mandatory_tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false # Hard-coded compliance: no public API
    security_group_ids      = var.security_group_ids
  }

  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(var.tags, local.mandatory_tags)

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
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
