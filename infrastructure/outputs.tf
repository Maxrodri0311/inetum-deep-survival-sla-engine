# Infrastructure Outputs for inetum-deep-survival-sla-engine

output "s3_telemetry_lake_bucket_name" {
  description = "Canonical S3 Bucket identifier for historical SLA Parquet telemetry"
  value       = aws_s3_bucket.telemetry_lake.id
}

output "s3_telemetry_lake_bucket_arn" {
  description = "Amazon Resource Name (ARN) for the telemetry data lake bucket"
  value       = aws_s3_bucket.telemetry_lake.arn
}

output "rds_postgres_endpoint" {
  description = "Direct connection endpoint for the PostgreSQL SLA telemetry cluster"
  value       = aws_db_instance.telemetry_postgres.endpoint
}

output "rds_postgres_database_name" {
  description = "Target database name hosting continuous rollup and cohort tables"
  value       = aws_db_instance.telemetry_postgres.db_name
}

output "iam_task_execution_role_arn" {
  description = "IAM role ARN assumed by DeepSurv inference workers"
  value       = aws_iam_role.deepsurv_task_execution_role.arn
}

output "cloudwatch_high_hazard_alarm_arn" {
  description = "CloudWatch alarm ARN monitoring SLA breach hazard anomalies"
  value       = aws_cloudwatch_metric_alarm.high_sla_breach_hazard.arn
}