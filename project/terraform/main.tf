# =============================================================================
# Root main.tf — Orchestrates all modules
#
# Interview note:
#   We use a modular structure so each concern (VPC, ASG, ALB, etc.) is
#   independently testable, reusable across environments, and reviewable
#   in isolation. Root main.tf is kept thin — it only wires modules together.
# =============================================================================

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Module: VPC
#
# Why: Isolates all application traffic inside a private network.
# Two public subnets for ALB, two private subnets for EC2 app servers.
# NAT Gateway allows private instances to pull ECR images outbound.
# ---------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

# ---------------------------------------------------------------------------
# Module: Security Groups
#
# Why: Principle of least privilege. Each tier (ALB, App, Jenkins) gets
# only the ports it needs. This is the first line of network defence.
# ---------------------------------------------------------------------------
module "security_groups" {
  source = "./modules/security_groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  app_port     = var.app_port
}

# ---------------------------------------------------------------------------
# Module: IAM
#
# Why: EC2 app servers and Jenkins need scoped IAM roles — not static keys.
# Using instance profiles means zero credentials stored on disk.
# ---------------------------------------------------------------------------
module "iam" {
  source = "./modules/iam"

  project_name   = var.project_name
  environment    = var.environment
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = var.aws_region
}

# ---------------------------------------------------------------------------
# Module: ECR
#
# Why: Private Docker registry inside AWS — no DockerHub rate limits,
# scanned automatically for CVEs, integrated with IAM.
# ---------------------------------------------------------------------------
module "ecr" {
  source = "./modules/ecr"

  project_name            = var.project_name
  environment             = var.environment
  image_retention_count   = var.ecr_image_retention_count
}

# ---------------------------------------------------------------------------
# Module: ALB (Application Load Balancer)
#
# Why: Layer-7 load balancer enables path-based routing, health checks,
# SSL termination, and zero-downtime rolling deployments.
# ---------------------------------------------------------------------------
module "alb" {
  source = "./modules/alb"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  alb_sg_id          = module.security_groups.alb_sg_id
  app_port           = var.app_port
}

# ---------------------------------------------------------------------------
# Module: Auto Scaling Group
#
# Why: Ensures the application is Highly Available, fault-tolerant, and
# can scale horizontally under load. Combined with ALB target group,
# ASG drains connections before terminating instances (zero-downtime).
# ---------------------------------------------------------------------------
module "asg" {
  source = "./modules/asg"

  project_name               = var.project_name
  environment                = var.environment
  ami_id                     = var.ami_id
  instance_type              = var.instance_type
  app_sg_id                  = module.security_groups.app_sg_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  target_group_arn           = module.alb.target_group_arn
  iam_instance_profile_name  = module.iam.app_instance_profile_name
  asg_min_size               = var.asg_min_size
  asg_max_size               = var.asg_max_size
  asg_desired_capacity       = var.asg_desired_capacity
  app_port                   = var.app_port
  ecr_repository_url         = module.ecr.repository_url
  aws_region                 = var.aws_region
  project_name               = var.project_name
}

# ---------------------------------------------------------------------------
# Module: Jenkins EC2
#
# Why: Dedicated build server with IAM role that can push to ECR and
# call EC2/ASG APIs. Isolated from application traffic.
# ---------------------------------------------------------------------------
module "jenkins" {
  source = "./modules/jenkins"

  project_name              = var.project_name
  environment               = var.environment
  ami_id                    = var.ami_id
  instance_type             = var.jenkins_instance_type
  key_name                  = var.jenkins_key_name
  jenkins_sg_id             = module.security_groups.jenkins_sg_id
  public_subnet_id          = module.vpc.public_subnet_ids[0]
  iam_instance_profile_name = module.iam.jenkins_instance_profile_name
}

# ---------------------------------------------------------------------------
# Module: CloudWatch
#
# Why: Observability is non-negotiable in production. CPU alarms drive
# ASG scaling policies. Log groups centralise application logs.
# ---------------------------------------------------------------------------
module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name             = var.project_name
  environment              = var.environment
  asg_name                 = module.asg.asg_name
  alb_arn_suffix           = module.alb.alb_arn_suffix
  target_group_arn_suffix  = module.alb.target_group_arn_suffix
  scale_out_policy_arn     = module.asg.scale_out_policy_arn
  scale_in_policy_arn      = module.asg.scale_in_policy_arn
  cpu_alarm_threshold      = var.cpu_alarm_threshold
  alarm_evaluation_periods = var.alarm_evaluation_periods
  alarm_period_seconds     = var.alarm_period_seconds
}
