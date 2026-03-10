# =============================================================================
# terraform/modules/atomic/s3-secure/outputs.tf
# =============================================================================

output "bucket_id" {
  description = "The S3 bucket name/ID."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket. Use in IAM policies granting access."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "The bucket domain name for use in CloudFront origins or pre-signed URL generation."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The bucket's regional domain name. Preferred over bucket_domain_name for same-region access."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
