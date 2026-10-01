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
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "aws-ecs-app"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Fetch the current AWS account ID — used to construct ECR repository URLs
data "aws_caller_identity" "current" {}
