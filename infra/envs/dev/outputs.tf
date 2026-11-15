output "vpc_id" {
  description = "ID of the VPC."
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = module.network.vpc_cidr
}

output "azs" {
  description = "Availability Zones used."
  value       = module.network.azs
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = module.network.private_subnet_ids
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways."
  value       = module.network.nat_gateway_ids
}

output "alb_url" {
  description = "Public URL of the app (HTTP only, no domain yet)."
  value       = "http://${module.alb.dns_name}"
}

output "ecr_repository_url" {
  description = "URL of the ECR repository."
  value       = module.ecr.repository_url
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = module.ecs_service.cluster_name
}

output "service_name" {
  description = "Name of the ECS service."
  value       = module.ecs_service.service_name
}

output "log_group_name" {
  description = "CloudWatch log group of the app."
  value       = module.ecs_service.log_group_name
}

output "task_definition_arn" {
  description = "Task definition revision in the Terraform state (the service may run another after a rollback)."
  value       = module.ecs_service.task_definition_arn
}

output "container_name" {
  description = "Name of the app container in the task definition."
  value       = module.ecs_service.container_name
}

output "task_security_group_id" {
  description = "Security group of the app tasks."
  value       = module.ecs_service.security_group_id
}

output "db_address" {
  description = "Hostname of the RDS instance (private, reachable only from the app tasks)."
  value       = module.database.address
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret with the database credentials."
  value       = module.database.master_user_secret_arn
}
