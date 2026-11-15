# Bucket, key and region come from backend.hcl at init time.
terraform {
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
