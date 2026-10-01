# inetum-deep-survival-sla-engine - Enterprise Cloud Infrastructure (IaC)
# Target: Inetum Managed Services SLA Hazard Telemetry & Data Lakehouse

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "inetum-deep-survival-sla-engine"
      TargetRole  = "Senior Data Scientist"
      ManagedBy   = "Terraform"
      Environment = var.environment
      DataTier    = "MissionCritical"
    }
  }
}

# -----------------------------------------------------------------------------
# 1. S3 Telemetry Lakehouse for High-Throughput Parquet & Model Checkpoints
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "telemetry_lake" {
  bucket        = "inetum-deep-survival-sla-lake-${var.environment}"
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "telemetry_versioning" {
  bucket = aws_s3_bucket.telemetry_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "telemetry_crypto" {
  bucket = aws_s3_bucket.telemetry_lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "telemetry_guard" {
  bucket                  = aws_s3_bucket.telemetry_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "telemetry_lifecycle" {
  bucket = aws_s3_bucket.telemetry_lake.id

  rule {
    id     = "archive-historical-sla-observations"
    status = "Enabled"

    filter {
      prefix = "telemetry/raw/"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# -----------------------------------------------------------------------------
# 2. Managed RDS PostgreSQL for Cohort Analytics & SLA Breach Audit Logs
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "sla_rds_subnets" {
  name        = "inetum-survival-rds-subnet-group"
  description = "Isolated subnets for Inetum SLA telemetry database"
  subnet_ids  = var.private_subnet_ids
}

resource "aws_security_group" "rds_sg" {
  name        = "inetum-survival-rds-sg"
  description = "Inbound access for DeepSurv inference workers to PostgreSQL telemetry"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL port from internal ECS tasks"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "telemetry_postgres" {
  identifier             = "inetum-sla-telemetry-db"
  allocated_storage      = var.db_allocated_storage
  max_allocated_storage  = 100
  engine                 = "postgres"
  engine_version         = "16.1"
  instance_class         = var.db_instance_class
  db_name                = "inetum_sla_analytics"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.sla_rds_subnets.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = false

  backup_retention_period = 7
  storage_encrypted       = true
  deletion_protection     = false
}

# -----------------------------------------------------------------------------
# 3. IAM Least-Privilege Execution Role & CloudWatch Telemetry Monitor
# -----------------------------------------------------------------------------
resource "aws_iam_role" "deepsurv_task_execution_role" {
  name = "inetum-deepsurv-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_lake_access" {
  name = "inetum-deepsurv-s3-lake-policy"
  role = aws_iam_role.deepsurv_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.telemetry_lake.arn,
          "${aws_s3_bucket.telemetry_lake.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "survival_engine_logs" {
  name              = "/aws/ecs/inetum-deep-survival-sla-engine"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_metric_alarm" "high_sla_breach_hazard" {
  alarm_name          = "inetum-high-sla-breach-hazard-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CriticalSLABreachEvents"
  namespace           = "Inetum/SLASurvival"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Triggers executive escalation when more than 5 SLA breach hazards are detected within 10 minutes."
}