output "alb_dns_name" {
  description = "Public DNS Name of the load balancer"
  value       = aws_lb.alb.dns_name
}

output "rds_endpoint" {
  description = "Endpoint of the RDS database"
  value       = aws_db_instance.default.endpoint
  sensitive   = true
}

output "vpc_id" {
  description = "AWS VPC ID"
  value       = aws_vpc.main.id
}

output "ecs_cluster_name" {
  description = "Describe the name of AWS ECS Cluster"
  value       = aws_ecs_cluster.app.name
}

output "secret_arn" {
  description = "Describe the AWS secret arn"
  value       = aws_secretsmanager_secret.rds_db_secret.arn
}

output "ecr_repository_url" {
  description = "ECR repository URL for pushing images"
  value       = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

