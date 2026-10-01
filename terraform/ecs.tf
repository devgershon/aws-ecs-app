# ──────────────────────────────────────────────
# ECS — Cluster, Task Definition, Service
# ──────────────────────────────────────────────

# ── Cluster ───────────────────────────────────
# A logical grouping for ECS services and tasks.
# With Fargate, the cluster is just a namespace — AWS manages
# the underlying compute.
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  # Container Insights — sends metrics to CloudWatch (CPU, memory, network).
  # Slightly more expensive but gives you visibility into container health.
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.project_name}-cluster" }
}

# ── IAM ───────────────────────────────────────

# Task execution role — used by ECS to pull the image from ECR
# and write logs to CloudWatch. This is NOT the role your app code uses.
data "aws_iam_policy_document" "ecs_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.project_name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
  description        = "Allows ECS to pull ECR images and write CloudWatch logs"
}

# AWS managed policy — grants exactly the permissions ECS needs for execution
resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# CloudWatch log group for container logs
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 14
}

# ── Task Definition ────────────────────────────
# Describes the container: which image, how much CPU/memory,
# environment variables, port mappings, and logging config.
resource "aws_ecs_task_definition" "app" {
  family                   = var.project_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"  # Required for Fargate
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([
    {
      name      = var.project_name
      image     = "${aws_ecr_repository.app.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = var.app_port
          protocol      = "tcp"
        }
      ]

      # Environment variables injected into the container at runtime
      environment = [
        { name = "BLOG_API_URL",    value = var.blog_api_url },
        { name = "ALLOWED_ORIGIN",  value = var.allowed_origin },
        { name = "ENVIRONMENT",     value = var.environment },
      ]

      # Send container logs to CloudWatch
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # Health check mirrors the Dockerfile HEALTHCHECK
      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${var.app_port}/health')\""]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }
    }
  ])

  tags = { Name = "${var.project_name}-task" }
}

# ── Service ────────────────────────────────────
# Keeps the desired number of task instances running at all times.
# Handles rolling deploys — starts new tasks, waits for health checks,
# then drains and stops old tasks.
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Rolling deploy settings:
  # - minimum 100% healthy during deploy (never go below desired count)
  # - maximum 200% allows new tasks to start before old ones stop
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true  # Required for Fargate in a public subnet to pull ECR images
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.project_name
    container_port   = var.app_port
  }

  # Ignore task_definition changes from Terraform after initial deploy.
  # The CI/CD pipeline updates the task definition directly —
  # we don't want terraform apply to revert those changes.
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.ecs_execution,
  ]

  tags = { Name = "${var.project_name}-service" }
}
