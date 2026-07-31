terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state backend — use S3 + DynamoDB for team collaboration
  # Uncomment after creating the bucket and table manually (bootstrapping)
  # backend "s3" {
  #   bucket         = "enterprisebot-tfstate-ap-south-1"
  #   key            = "production/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "enterprisebot-tfstate-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "platform-engineering"
    }
  }
}
