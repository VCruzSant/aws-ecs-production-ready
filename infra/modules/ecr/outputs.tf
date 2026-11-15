output "repository_name" {
  description = "Name of the repository."
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "URL of the repository, used as the image name in docker push and in the task definition."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the repository, used to scope IAM pull permissions."
  value       = aws_ecr_repository.this.arn
}
