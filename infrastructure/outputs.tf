# inetum_senior_data_scientist_bridge_project - Infrastructure Outputs

output "telemetry_bucket_arn" {
  description = "ARN of the primary telemetry data lake bucket"
  value       = aws_s3_bucket.telemetry_lake.arn
}

output "execution_role_arn" {
  description = "IAM Role ARN for analytical workloads"
  value       = aws_iam_role.analytics_execution_role.arn
}