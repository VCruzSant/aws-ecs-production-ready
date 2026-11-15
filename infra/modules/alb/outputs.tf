output "dns_name" {
  description = "Public DNS name of the load balancer."
  value       = aws_lb.this.dns_name
}

output "arn_suffix" {
  description = "ARN suffix of the load balancer, used in CloudWatch metrics."
  value       = aws_lb.this.arn_suffix
}

output "security_group_id" {
  description = "Security group of the load balancer."
  value       = aws_security_group.this.id
}

# ECS rejects a target group that is not attached to a load balancer yet.
output "target_group_arn" {
  description = "ARN of the target group the ECS service registers its tasks in."
  value       = aws_lb_target_group.app.arn
  depends_on  = [aws_lb_listener.http]
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the target group, used in CloudWatch metrics."
  value       = aws_lb_target_group.app.arn_suffix
}

output "access_logs_bucket" {
  description = "Name of the S3 bucket with the access logs (null when they are off)."
  value       = one(aws_s3_bucket.access_logs[*].id)
}
