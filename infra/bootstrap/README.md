# Bootstrap

Runs once per account, with local state. Nothing here is removed by `make tf-destroy`, and nothing here costs more than a few cents per month.

| Resource | Why it lives here |
|---|---|
| S3 bucket for the Terraform state | Every environment keeps its state in it, so it has to exist first and outlive them. `prevent_destroy` protects it. |
| AWS Budget with e-mail alerts | Watches the whole account, not one environment. |
| GitHub OIDC provider | One per account. It lets GitHub Actions get short-lived AWS credentials, so no AWS key is stored in GitHub. |
| GitHub deploy role | Used by `.github/workflows/deploy.yml`. Created only when `github_repository` is set. |

## Deploy role

Only jobs of the repository in `github_repository` that run in the GitHub environment `deploy_environment` can assume it. The trust policy checks the token audience (`sts.amazonaws.com`) and its subject, `repo:<owner>/<repo>:environment:<deploy_environment>`. Jobs that do not run in that environment get no credentials.

Its permissions are built from the names the environment will have (`<project>-<deploy_environment>`), so the bootstrap never reads the environment state and the role can exist while the environment is destroyed:

- Push to the app ECR repository, and `ecr:GetAuthorizationToken` on `*` (no resource-level permissions).
- `ecs:DescribeTaskDefinition` on `*` (no resource-level permissions, read only).
- Register revisions of the app task definition family, tagging them only while registering.
- Describe and update the app service, only to a revision of the app family.
- Run the migration task in the app cluster and describe its tasks.
- `iam:PassRole` on the task execution role and the task role only, and only to `ecs-tasks.amazonaws.com`.
- Read the app log streams, to print the migration log.

The role cannot run Terraform, read secrets, or touch anything outside the app service.

If the account already has the GitHub OIDC provider, import it before applying:

```bash
terraform import 'aws_iam_openid_connect_provider.github[0]' arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
```

## Variables

| Name | Default | Description |
|---|---|---|
| `budget_alert_emails` | (required) | Addresses that receive the budget alerts |
| `region` | `us-east-2` | Region of the bucket and the budget |
| `project` | `aws-ecs-production-ready` | Name used in the budget, the tags and the deploy role permissions |
| `state_bucket_prefix` | `aws-ecs-prod-ready-tfstate` | Bucket name is `<prefix>-<account-id>` |
| `monthly_budget_usd` | `10` | Budget limit per month |
| `noncurrent_version_retention_days` | `90` | Days to keep old state versions |
| `github_repository` | `null` | `owner/name` of the repository allowed to deploy. Null skips the OIDC provider and the role |
| `deploy_environment` | `dev` | Environment the role deploys to, and the GitHub environment allowed to assume it |
| `deploy_region` | `region` | Region of that environment |

## Outputs

| Name | Description |
|---|---|
| `state_bucket_name` | Bucket for `backend.hcl` |
| `region` | Region of the bucket |
| `budget_name` | Name of the budget |
| `github_deploy_role_arn` | Role for `AWS_DEPLOY_ROLE_ARN` in the GitHub environment (null without `github_repository`) |
