variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-west-2"
}

variable "environment" {
  description = "Deployment environment label."
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Used to name all resources consistently."
  type        = string
  default     = "portfolio-api"
}

variable "blog_api_url" {
  description = "The Project 2 Lambda API base URL — injected into the ECS container as an env var."
  type        = string
  default     = "https://t0tn9g17b7.execute-api.eu-west-2.amazonaws.com"
}

variable "allowed_origin" {
  description = "Portfolio site CloudFront URL — used for CORS."
  type        = string
  default     = "https://d2eeybsp9y6gvd.cloudfront.net"
}

variable "app_port" {
  description = "Port the FastAPI app listens on inside the container."
  type        = number
  default     = 8000
}

variable "fargate_cpu" {
  description = "CPU units for the Fargate task (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "fargate_memory" {
  description = "Memory for the Fargate task in MB."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of ECS task instances to run."
  type        = number
  default     = 1
}
