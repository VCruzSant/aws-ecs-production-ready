# Remote state in S3 with native locking (Terraform >= 1.10): no DynamoDB table.
# Bucket and region come from the bootstrap, so they are passed at init time:
#   terraform init -backend-config=backend.hcl
# (see backend.hcl.example).
terraform {
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
