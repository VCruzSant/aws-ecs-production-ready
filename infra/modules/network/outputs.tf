output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability Zones used, in the same order as the subnet lists."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, one per AZ."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, one per AZ."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways (empty when enable_nat_gateway = false)."
  value       = aws_nat_gateway.this[*].id
}

output "flow_logs_log_group_name" {
  description = "CloudWatch log group of the VPC Flow Logs (null when they are off)."
  value       = one(aws_cloudwatch_log_group.flow_logs[*].name)
}
