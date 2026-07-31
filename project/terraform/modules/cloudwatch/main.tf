# =============================================================================
# CloudWatch — Monitoring, Alarms, and Log Groups
#
# Interview note:
#   Observability has three pillars: Metrics, Logs, and Traces.
#   Here we cover Metrics (CPU alarms → ASG scaling) and Logs (centralised
#   log group for application containers).  In production, add X-Ray for
#   distributed tracing.
# =============================================================================

# ---------------------------------------------------------------------------
# Log Group — application logs from EC2 containers
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/ec2/${var.project_name}/${var.environment}"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-logs"
  }
}

resource "aws_cloudwatch_log_group" "jenkins" {
  name              = "/aws/ec2/${var.project_name}/${var.environment}/jenkins"
  retention_in_days = 14
}

# ---------------------------------------------------------------------------
# CPU Alarms → Scaling Policies
# ---------------------------------------------------------------------------

# Scale OUT when average CPU > threshold for N consecutive periods
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.alarm_period_seconds
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "Scale out when average CPU exceeds ${var.cpu_alarm_threshold}%"
  alarm_actions       = [var.scale_out_policy_arn]

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
}

# Scale IN when average CPU < (threshold - 20) for N periods
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-${var.environment}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.alarm_period_seconds
  statistic           = "Average"
  threshold           = max(var.cpu_alarm_threshold - 20, 10)
  alarm_description   = "Scale in when average CPU drops"
  alarm_actions       = [var.scale_in_policy_arn]

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
}

# ---------------------------------------------------------------------------
# ALB 5xx Error Rate Alarm
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_description   = "Alert when more than 10 backend 5xx errors in 1 minute"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
}

# ---------------------------------------------------------------------------
# ALB Unhealthy Host Alarm
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project_name}-${var.environment}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "Alert when any target is unhealthy"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Dashboard
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0; y = 0; width = 12; height = 6
        properties = {
          title   = "ASG CPU Utilization"
          metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name]]
          period  = 60
          stat    = "Average"
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12; y = 0; width = 12; height = 6
        properties = {
          title   = "ALB Request Count"
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix]]
          period  = 60
          stat    = "Sum"
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0; y = 6; width = 12; height = 6
        properties = {
          title   = "ALB 5xx Errors"
          metrics = [["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix]]
          period  = 60
          stat    = "Sum"
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12; y = 6; width = 12; height = 6
        properties = {
          title   = "Unhealthy Hosts"
          metrics = [["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix]]
          period  = 60
          stat    = "Average"
          view    = "timeSeries"
        }
      }
    ]
  })
}
