# =============================================================================
# Application Load Balancer
#
# Interview note:
#   ALB is a Layer-7 load balancer. It terminates HTTP/HTTPS connections,
#   performs health checks against the /healthz endpoint, and forwards traffic
#   to healthy EC2 instances only.  Connection draining (deregistration_delay)
#   gives in-flight requests time to complete before an instance is terminated
#   — this is what enables zero-downtime rolling deployments.
# =============================================================================

resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false # Set true in production after initial deploy

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb"
  }
}

# ---------------------------------------------------------------------------
# S3 Bucket for ALB access logs
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.project_name}-${var.environment}-alb-logs"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-logs"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter { prefix = "alb/" }

    expiration {
      days = 30
    }
  }
}

data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.main.arn }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/*"
    }]
  })
}

# ---------------------------------------------------------------------------
# Target Group
# ---------------------------------------------------------------------------
resource "aws_lb_target_group" "app" {
  name                 = "${var.project_name}-${var.environment}-tg"
  port                 = var.app_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30 # seconds — wait for in-flight requests to finish

  health_check {
    enabled             = true
    path                = "/healthz"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-tg"
  }
}

# ---------------------------------------------------------------------------
# HTTP Listener — redirect to HTTPS in production
# For assessment purposes we serve directly on HTTP 80
# ---------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
