output "bucket_name" {
  description = "Nome do bucket SSM"
  value       = aws_s3_bucket.ssm.bucket
}

output "bucket_arn" {
  description = "ARN do bucket SSM"
  value       = aws_s3_bucket.ssm.arn
}
