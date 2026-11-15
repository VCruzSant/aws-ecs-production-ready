# Bucket and region are passed at init time: terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
