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
