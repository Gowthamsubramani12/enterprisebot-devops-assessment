# =============================================================================
# Auto Scaling Group
#
# Interview note:
#   We use a Launch Template (not the deprecated Launch Configuration) because
#   it supports versioning — every change creates a new version, and Instance
#   Refresh uses it to perform a rolling replacement of instances.
#
#   Rolling update strategy:
#   - MinHealthyPercentage = 50%: keeps at least half the fleet alive during refresh
#   - InstanceWarmup = 120s: waits for health checks to pass before continuing
#   This gives us zero-downtime rolling deployments without any external tooling.
# =============================================================================

locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    ecr_repository_url = var.ecr_repository_url
    aws_region         = var.aws_region
    app_port           = var.app_port
    project_name       = var.project_name
  }))
}

# ---------------------------------------------------------------------------
# Launch Template
# ---------------------------------------------------------------------------
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-${var.environment}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [var.app_sg_id]

  iam_instance_profile {
    name = var.iam_instance_profile_name
  }

  user_data = local.user_data

  # Encrypt the root EBS volume for compliance
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true # Enable detailed 1-minute CloudWatch metrics
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-${var.environment}-app"
      Environment = var.environment
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Auto Scaling Group
# ---------------------------------------------------------------------------
resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-${var.environment}-asg"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [var.target_group_arn]
  health_check_type   = "ELB"  # ALB health checks govern instance health
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Rolling instance refresh — used by Jenkins pipeline on every deployment
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-app"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity] # Let ASG manage capacity after initial deploy
  }
}

# ---------------------------------------------------------------------------
# Scaling Policies — triggered by CloudWatch alarms
# ---------------------------------------------------------------------------
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project_name}-${var.environment}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.project_name}-${var.environment}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}
