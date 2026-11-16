output "state_bucket_name" {
  description = "Name of the S3 bucket that stores the Terraform state."
  value       = aws_s3_bucket.state.bucket
}

output "region" {
  description = "Region of the state bucket."
  value       = var.region
}

output "budget_name" {
  description = "Name of the monthly cost budget."
  value       = aws_budgets_budget.monthly.name
}

output "github_deploy_role_arn" {
  description = "ARN of the role GitHub Actions assumes to deploy (AWS_DEPLOY_ROLE_ARN in the GitHub environment)."
  value       = one(aws_iam_role.github_deploy[*].arn)
}
