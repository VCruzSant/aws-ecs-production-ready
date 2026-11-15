#trivy:ignore:AWS-0033 AES256 encrypts the images at rest; a KMS key adds cost and no protection here.
resource "aws_ecr_repository" "this" {
  #checkov:skip=CKV_AWS_136:AES256 encrypts the images at rest; a KMS key adds cost and no protection here.
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"

  # Lets terraform destroy remove the repository even when it still holds images.
  force_delete = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the ${var.max_image_count} most recent tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.max_image_count
        }
        action = { type = "expire" }
      },
    ]
  })
}
