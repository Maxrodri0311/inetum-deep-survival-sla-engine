# inetum_senior_data_scientist_bridge_project - Enterprise Infrastructure as Code (IaC)
# Generated autonomously by ATS-Engine Scaffolder v5.2

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project     = "inetum_senior_data_scientist_bridge_project"
      TargetRole  = "Senior Data Scientist"
      ManagedBy   = "Terraform"
      Environment = "Production"
    }
  }
}

resource "aws_s3_bucket" "telemetry_lake" {
  bucket        = "inetum-finance-linear-optimization-engine-telemetry-lake"
  force_destroy = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "telemetry_crypto" {
  bucket = aws_s3_bucket.telemetry_lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role" "analytics_execution_role" {
  name = "inetum_senior_data_scientist_bridge_project_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}