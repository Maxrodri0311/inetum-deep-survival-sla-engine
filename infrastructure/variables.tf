# Variables declaration for inetum-deep-survival-sla-engine infrastructure

variable "aws_region" {
  description = "AWS deployment region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Target deployment environment (production, staging)"
  type        = string
  default     = "production"
}

variable "vpc_id" {
  description = "Virtual Private Cloud identifier"
  type        = string
  default     = "vpc-0a1b2c3d4e5f6g7h8"
}

variable "vpc_cidr" {
  description = "VPC CIDR block for internal security group rules"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for RDS multi-AZ placement"
  type        = list(string)
  default     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
}

variable "db_instance_class" {
  description = "Database compute sizing"
  type        = string
  default     = "db.t4g.medium"
}

variable "db_allocated_storage" {
  description = "Initial storage allocated for PostgreSQL telemetry in GB"
  type        = number
  default     = 20
}

variable "db_username" {
  description = "Master administrative username for PostgreSQL telemetry"
  type        = string
  default     = "inetum_sla_admin"
}

variable "db_password" {
  description = "Master administrative password for PostgreSQL telemetry"
  type        = string
  sensitive   = true
  default     = "InetumSecureSurvivalSLA2026!"
}

variable "log_retention_days" {
  description = "CloudWatch log retention window in days"
  type        = number
  default     = 30
}
