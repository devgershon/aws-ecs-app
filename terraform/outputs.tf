output "alb_url" {
  description = "Your app is live at this URL."
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "ECR repository URL — used in the CI/CD pipeline to push images."
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name — used in the GitHub Actions deploy step."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name — used in the GitHub Actions deploy step."
  value       = aws_ecs_service.app.name
}

output "ecs_task_definition_family" {
  description = "ECS task definition family name."
  value       = aws_ecs_task_definition.app.family
}
