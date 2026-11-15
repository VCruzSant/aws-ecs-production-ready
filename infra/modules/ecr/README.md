# Module: ecr

A private ECR repository for one app image.

- **Immutable tags.** A tag always points to the same image, so a task definition that says `my-app:abc1234` runs exactly what was tested. Pushing a different image under an existing tag fails.
- **Scan on push.** Every pushed image gets an ECR basic scan for known CVEs in OS packages. Results are in the console or `aws ecr describe-image-scan-findings`.
- **Lifecycle policy.** Untagged images expire one day after the push. Of the tagged images, only the most recent are kept (20 by default), so storage cost stays flat. The count includes the image in use: ECR does not know what ECS is running, so if more than `max_image_count` images are pushed without deploying them, the running tag expires and a replaced task cannot pull it. Keep the number well above the pushes between two deploys.
- **`force_delete`.** On by default so `terraform destroy` removes the repository even when it still holds images. Turn it off for a repository that must outlive the environment.

Basic scanning does not support image indexes. Build with `docker build --provenance=false` so the push is a single image manifest.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | (required) | Repository name (lowercase) |
| `max_image_count` | `number` | `20` | Number of most recent tagged images to keep |
| `force_delete` | `bool` | `true` | Delete the repository on destroy even if it has images |
| `tags` | `map(string)` | `{}` | Extra tags for the repository |

## Outputs

| Name | Description |
|---|---|
| `repository_name` | Name of the repository |
| `repository_url` | URL used as the image name in `docker push` and in the task definition |
| `repository_arn` | ARN used to scope IAM pull permissions |

## Usage

```hcl
module "ecr" {
  source = "../../modules/ecr"

  name = "my-app-dev"
}

# Then, for example:
#   image = "${module.ecr.repository_url}:${var.image_tag}"
```

Requires Terraform `>= 1.10` and the AWS provider `~> 6.73`.
