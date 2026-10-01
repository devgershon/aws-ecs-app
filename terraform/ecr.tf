# ──────────────────────────────────────────────
# ECR — Elastic Container Registry
# ──────────────────────────────────────────────
# ECR is AWS's private Docker image registry.
# Every time the CI/CD pipeline builds a new version of the app,
# it pushes the image here. ECS then pulls from here when deploying.
# ──────────────────────────────────────────────

resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE" # Allows reusing tags like "latest"

  # Scan images for known vulnerabilities on every push.
  # Results appear in the ECR console — free to enable.
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = var.project_name
  }
}

# Lifecycle policy — automatically delete old images to keep storage costs down.
# Keeps the last 10 images and deletes anything older.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
