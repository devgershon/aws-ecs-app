# ──────────────────────────────────────────────
# Application Load Balancer
# ──────────────────────────────────────────────
# The ALB sits in front of the ECS service and:
#   1. Gives you a stable public DNS name (no matter how many times
#      containers restart and get new IPs)
#   2. Performs health checks and stops routing to unhealthy containers
#   3. Enables rolling deploys — routes to new containers only after
#      they pass health checks, then drains old ones
# ──────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false          # Public-facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  # Prevent accidental deletion — remove this if you want terraform destroy to work cleanly
  enable_deletion_protection = false

  tags = { Name = "${var.project_name}-alb" }
}

# Target Group — the group of ECS tasks the ALB routes traffic to
resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Required for Fargate — tasks use IPs, not instance IDs

  # Health check — ALB calls /health every 30 seconds.
  # A task must pass 2 consecutive checks to be considered healthy.
  # A task must fail 3 consecutive checks to be removed from rotation.
  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = { Name = "${var.project_name}-tg" }
}

# Listener — tells the ALB to accept HTTP traffic on port 80
# and forward it to the target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
