# =============================================================================
# ECR Repository
#
# Interview note:
#   ECR is the natural choice when running on AWS — no Docker Hub rate limits,
#   images are encrypted at rest with KMS, vulnerability scanning is built-in,
#   and IAM controls push/pull access.  We set a lifecycle policy to keep only
#   the last N tagged images and clean up untagged ones automatically.
# =============================================================================

resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # Auto-scan every image pushed for CVEs
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-ecr"
  }
}

# ---------------------------------------------------------------------------
# Lifecycle Policy — keep last N tagged images, expire untagged immediately
# ---------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images immediately"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${var.image_retention_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = var.image_retention_count
        }
        action = { type = "expire" }
      }
    ]
  })
}
