# =============================================================================
# General
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
  default     = "enterprisebot"
}

variable "environment" {
  description = "Deployment environment (production, staging, dev)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "dev"], var.environment)
    error_message = "environment must be one of: production, staging, dev."
  }
}

# =============================================================================
# VPC & Networking
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to use in ap-south-1"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

# =============================================================================
# EC2 / ASG
# =============================================================================

variable "instance_type" {
  description = "EC2 instance type for application servers"
  type        = string
  default     = "t3.small"
}

variable "ami_id" {
  description = "Amazon Linux 2023 AMI ID for ap-south-1"
  type        = string
  default     = "ami-0f58b397bc5c1f2e8" # Amazon Linux 2023 ap-south-1 — update periodically
}

variable "asg_min_size" {
  description = "Minimum number of EC2 instances in the ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances in the ASG"
  type        = number
  default     = 6
}

variable "asg_desired_capacity" {
  description = "Desired number of EC2 instances in the ASG"
  type        = number
  default     = 2
}

variable "app_port" {
  description = "Port the application container listens on"
  type        = number
  default     = 8080
}

# =============================================================================
# ECR
# =============================================================================

variable "ecr_image_retention_count" {
  description = "Number of Docker images to retain per ECR repository"
  type        = number
  default     = 10
}

# =============================================================================
# Jenkins EC2
# =============================================================================

variable "jenkins_instance_type" {
  description = "EC2 instance type for the Jenkins server"
  type        = string
  default     = "t3.medium"
}

variable "jenkins_key_name" {
  description = "Name of the EC2 Key Pair for Jenkins SSH access"
  type        = string
  default     = "enterprisebot-jenkins-key"
}

# =============================================================================
# CloudWatch
# =============================================================================

variable "cpu_alarm_threshold" {
  description = "CPU utilization percentage to trigger scale-out"
  type        = number
  default     = 70
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods before triggering alarm"
  type        = number
  default     = 2
}

variable "alarm_period_seconds" {
  description = "CloudWatch alarm evaluation period in seconds"
  type        = number
  default     = 120
}
