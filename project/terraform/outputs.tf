output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for pushing/pulling Docker images"
  value       = module.ecr.repository_url
}

output "jenkins_public_ip" {
  description = "Public IP of the Jenkins EC2 instance"
  value       = module.jenkins.public_ip
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.asg.asg_name
}

output "cloudwatch_log_group" {
  description = "Name of the CloudWatch log group for the application"
  value       = module.cloudwatch.log_group_name
}

output "aws_account_id" {
  description = "AWS account ID (used in ECR image paths)"
  value       = data.aws_caller_identity.current.account_id
}
