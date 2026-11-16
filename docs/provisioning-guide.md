# Provisioning guide

How to build this stack from zero in any AWS account, under any project name. Follow the steps in order. You do not need to open a `.tf` file: everything you can change is listed here.

What you get: a VPC, an ECR repository, an Application Load Balancer, the API on ECS Fargate in private subnets and a PostgreSQL database on RDS. See [infra/README.md](../infra/README.md) for how each part works and the [security and cost review](security-review.md) for the decisions behind it.

## 1. Prerequisites

| Tool | Minimum | Check |
|---|---|---|
| Terraform | 1.10 (native S3 state locking) | `terraform version` |
| AWS CLI | v2 | `aws --version` |
| Docker | with BuildKit | `docker version` |
| GNU Make | any | `make --version` |
| uv | any (only for `make test` and `make lint`) | `uv --version` |

You also need an AWS account and a CLI profile for it. Use IAM Identity Center (`aws configure sso`) or a role with temporary credentials. Never use the root user and avoid long-lived access keys.

```bash
export AWS_PROFILE=<your-profile>
aws sts get-caller-identity
```

Expected: the account ID and role you mean to deploy to. If it is the wrong account, stop here. Every later step runs against it.

## 2. Choose the region

Pick a region and check that the account can create resources there. New accounts on the AWS Free Tier have a home region, and a service control policy (SCP) can deny almost everything elsewhere.

```bash
aws ec2 create-vpc --dry-run --cidr-block 10.0.0.0/16 --region <region>
```

The command creates nothing. `DryRunOperation` ("Request would have succeeded") means the region is usable. `UnauthorizedOperation` means a policy denies it: choose another region, usually the home region shown in the account's billing page.

The defaults use `us-east-2`. Any region works if you follow the extra steps in [Using another region](#using-another-region).

## 3. Bootstrap the state and the budget

The bootstrap creates the S3 bucket that holds the Terraform state of every environment, and a monthly AWS Budget with e-mail alerts. It runs once per account and keeps its own state on your machine.

```bash
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

| Variable | Meaning | Default |
|---|---|---|
| `budget_alert_emails` | Addresses that receive the budget alerts (required) | none |
| `monthly_budget_usd` | Budget limit per month | `10` |
| `project` | Name used in the budget and the tags | `aws-ecs-production-ready` |
| `state_bucket_prefix` | Bucket name is `<prefix>-<account-id>` | `aws-ecs-prod-ready-tfstate` |
| `region` | Region of the bucket and the budget | `us-east-2` |
| `noncurrent_version_retention_days` | Days to keep old state versions | `90` |
| `github_repository` | `owner/name` of the repository that deploys through GitHub Actions. Leave it out to skip continuous deployment | none |
| `deploy_environment` | Environment the deploy role can change, and the GitHub environment allowed to use it | `dev` |

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output
cd ../..
```

`init` downloads the AWS provider, `plan` shows the bucket and budget, plus the OIDC provider and deploy role when `github_repository` is set (nothing is created yet), and `apply` creates them. Expected: `state_bucket_name` and `region` in the output, and `github_deploy_role_arn` with continuous deployment. Note them: the next steps need them.

Keep `infra/bootstrap/terraform.tfstate`. It is the only record Terraform has of the bucket and the budget, and it is git-ignored.

## 4. Create the environment

Each environment is a folder in `infra/envs/`. The repository ships `dev`. To create another one, copy it and keep the files that are not versioned out of git:

```bash
cp -r infra/envs/dev infra/envs/staging    # skip this line for dev
cd infra/envs/staging
rm -rf .terraform backend.hcl terraform.tfvars tfplan
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

Edit `backend.hcl`:

| Key | Value |
|---|---|
| `bucket` | `state_bucket_name` from the bootstrap |
| `key` | `envs/<env>/terraform.tfstate`, with the same name as the folder |
| `region` | `region` from the bootstrap |

Edit `terraform.tfvars` (every line is optional, the commented defaults apply otherwise):

| Variable | What it changes | Default |
|---|---|---|
| `project` | Prefix of every resource name and the `Project` tag. Resources are named `<project>-<env>` | `aws-ecs-production-ready` |
| `region` | Region of the environment. Must match `backend.hcl` unless you want the state in another region | `us-east-2` |
| `vpc_cidr` | VPC address range. Change it if you will peer VPCs | `10.0.0.0/16` |
| `az_count` | Availability Zones used | `2` |
| `enable_nat_gateway` | NAT for the private subnets. Without it the tasks cannot pull images | `true` |
| `single_nat_gateway` | One shared NAT, or one per AZ for high availability (about twice the NAT cost) | `true` |
| `task_cpu`, `task_memory` | Fargate task size (256 CPU units = 0.25 vCPU, memory in MiB) | `256`, `512` |
| `desired_count` | Number of app tasks | `1` |
| `db_instance_class` | RDS instance size | `db.t4g.micro` |
| `db_multi_az` | Standby database in a second AZ, about twice the database cost | `false` |
| `container_insights` | CloudWatch Container Insights, extra cost | `false` |
| `enable_flow_logs`, `alb_access_logs` | Rejected-traffic logs and load balancer access logs, 7 days each | `true` |
| `app_port` | Port the container listens on | `8000` |

The environment name comes from the folder: `make` passes `ENV` to Terraform as the `environment` variable, so the name and the `Environment` tag cannot drift apart.

Check the whole thing with a plan before spending anything:

```bash
make tf-plan ENV=staging
```

Expected: `Plan: 53 to add, 0 to change, 0 to destroy.` and every name starting with `<project>-staging`. Nothing is created.

## 5. First deploy

```bash
make infra-up ENV=staging
```

It runs four steps and asks for confirmation before each `apply`:

| Step | What happens | Time |
|---|---|---|
| ECR | `terraform apply -target=module.ecr` creates only the image repository, because the service needs an image that does not exist yet | under 1 minute |
| Image | `make image-push` builds `app/` for `linux/amd64` and pushes it tagged with the short git SHA | 1 to 3 minutes |
| Everything else | `terraform apply` creates the network, load balancer, database and service, and waits until the service is stable | about 12 to 15 minutes, most of it the RDS instance |
| Migration | `make db-migrate` runs `alembic upgrade head` as a one-off ECS task | 1 to 2 minutes |

This is the only place where `-target` is used. `ENV` is the same on every command, so leaving it out would act on `dev`.

## 6. Verify

```bash
URL=$(terraform -chdir=infra/envs/staging output -raw alb_url)
curl -i "$URL/health"
curl -i "$URL/health/db"
curl -i -X POST "$URL/tasks" -H 'Content-Type: application/json' -d '{"title":"first"}'
curl -i "$URL/tasks"
aws logs tail "$(terraform -chdir=infra/envs/staging output -raw log_group_name)" --since 10m
```

Expected: `200` from both health checks, with `{"status":"ok","version":"<tag>"}` from `/health`, `201` from the POST, the task in the list and one JSON log line per request. If `/health` answers but `/health/db` returns `503`, see [Troubleshooting](#9-troubleshooting).

## 7. Later deploys

```bash
make image-push ENV=staging                          # skipped if that tag already exists in ECR
make tf-plan ENV=staging                             # review the plan
terraform -chdir=infra/envs/staging apply tfplan
make db-migrate ENV=staging                          # only needed when the release has migrations
```

The tag is the short SHA of the last commit that changed `app/`, with `-dirty` added for uncommitted changes. Tags are immutable. If the new tasks fail the load balancer health check, the deployment circuit breaker rolls back to the previous task definition. The deploy workflow automates these steps, see [Continuous deployment](#11-continuous-deployment).

## 8. Destroy

```bash
make tf-destroy ENV=staging
```

This removes everything in the environment: network, load balancer, service, database (without a final snapshot), ECR images and logs. The state bucket, the budget, the OIDC provider and the deploy role stay. They cost a few cents per month at most. To remove them as well, edit `prevent_destroy` in `infra/bootstrap/main.tf`, empty the bucket (versioned objects included) and run `terraform destroy` in `infra/bootstrap`. Do that only when no environment uses the state any more.

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `UnauthorizedOperation` or `explicit deny in a service control policy` | The account's SCP denies the region, or a spend limit is close (Free Tier accounts block ECS services, load balancers, RDS and NAT near the limit) | Use the account's home region, or move the account to the Paid Plan |
| `Error acquiring the state lock` | Another run is using the state, or a run was interrupted | Wait for the other run. If none is running, `terraform force-unlock <ID>` with the ID from the message |
| `Backend configuration changed` or the wrong state is used | `backend.hcl` points to another key or bucket | Fix `backend.hcl` and rerun `make tf-init ENV=<env>` |
| ECR image shows no vulnerability scan | The image was pushed as an index with provenance attestations, which basic scanning does not support | `make image-push` builds with `--provenance=false`. If you push by hand, add the flag |
| `terraform apply` hangs on the database for 10 minutes | Creating an RDS instance takes that long | Wait. Check the status in the RDS console if it passes 20 minutes |
| `/health/db` returns `503` | The migration did not run, or the task cannot reach the database | `make db-migrate ENV=<env>`, then read the app logs from step 6 |
| `make db-migrate` says "Still running after 10 minutes" | The waiter gave up before the task stopped | Do not start another migration. Run the `describe-tasks` command it prints and wait for the task to stop |
| `make db-migrate` says "Migration failed" | The migration command exited with an error | Read the log the target prints. Fix the migration and rerun |
| `certificate verify failed` in the app logs | The CA bundle in the image does not match the region | See [Using another region](#using-another-region) |
| `The ECS service did not stabilize` and a rollback | The new task fails the health check | Read the app logs. The previous version keeps serving |

## 10. Cost

The environments are meant to be created, validated and destroyed. With everything running, `dev` costs about $0.12 per hour (about $2.90 per day). After `make tf-destroy` only the state bucket and the budget remain, under $0.01 per month. The per-resource table and the cost of each variant are in the [infra README](../infra/README.md#cost-us-east-2-on-demand-prices) and the [security review](security-review.md#cost).

## 11. Continuous deployment

`.github/workflows/deploy.yml` deploys the app on every push to `main` that changes `app/`, and on a manual run. It authenticates with OIDC through the deploy role from the bootstrap, so GitHub holds no AWS key. When the environment is not running it ends green with "No environment running, skipping deploy". How each step works is in the [infra README](../infra/README.md#continuous-deployment).

Set it up once per repository:

1. Apply the bootstrap with `github_repository` set (step 3) and note `github_deploy_role_arn`.
2. In GitHub, open Settings, Environments, and create the environment `dev` (the value of `deploy_environment`). Optionally limit it to the `main` branch under deployment branches.
3. Add these environment variables (Variables, not Secrets: none of them is sensitive):

| Variable | Value |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | `github_deploy_role_arn` from the bootstrap |
| `AWS_REGION` | Region of the environment, for example `us-east-2` |
| `ECS_CLUSTER` | `<project>-<env>`, the `cluster_name` output |
| `ECS_SERVICE` | `<project>-<env>`, the `service_name` output |
| `ECR_REPOSITORY` | `<project>-<env>`, the last part of the `ecr_repository_url` output |
| `RDS_CA_SHA256` | Only outside `us-east-2`, see [Using another region](#using-another-region) |

The names follow the `<project>-<env>` convention, so you can set them before the environment exists. Until the variables are set, the workflow ends green with a warning that deploy is not configured.

The first deploy of an environment is still `make infra-up`, since the workflow only updates a running service. To redeploy, or to deploy another branch, run the workflow from the Actions tab with an optional `ref`.

| Symptom | Cause | Fix |
|---|---|---|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The job is not in the environment the role trusts, or `github_repository` does not match the repository | Check `deploy_environment` and `github_repository` in the bootstrap and the environment name in the workflow |
| `Deployment of <revision> failed and the circuit breaker rolled back` | The new tasks never passed the health check | Read the app logs. The previous revision keeps serving |
| `Migration failed` in the workflow | The migration exited with an error, so the service was not updated | Read the log printed by the step, fix the migration and push again |

## Using another region

The defaults assume `us-east-2`. For another region:

1. Set `region` in the bootstrap `terraform.tfvars`, the environment `terraform.tfvars` and `backend.hcl`.
2. Get the checksum of that region's RDS CA bundle. The image build verifies it, so a changed file fails the build:

   ```bash
   curl -s https://truststore.pki.rds.amazonaws.com/<region>/<region>-bundle.pem | sha256sum
   ```

3. Pass it to every image build: `make infra-up ENV=<env> RDS_CA_SHA256=<hash>` and `make image-push ENV=<env> RDS_CA_SHA256=<hash>`, and set it as `RDS_CA_SHA256` in the GitHub environment for the deploy workflow. The region itself is read from the ECR repository URL.
4. The load balancer access log bucket policy uses the regional Elastic Load Balancing account, which exists only in regions launched before August 2022. For a newer region, change the principal in `infra/modules/alb/main.tf` to the `logdelivery.elasticloadbalancing.amazonaws.com` service, or set `alb_access_logs = false`.

Prices differ between regions. Check them before quoting a client.

## Using this for a client

### Set up

- **Template.** Make one private copy of this repository per client, outside the public repository. The public repository stays as a portfolio.
- **Client's account.** Run everything in the client's AWS account. Ask for access through IAM Identity Center or a role with temporary credentials, limited to the services in this stack. Do not accept the root user or an IAM user with a long-lived key. The client owns the account, the bucket with the state and the bill.
- **Separate environments.** One folder per environment under `infra/envs/` (`dev`, `staging`, `prod`), each with its own state key. They can share one account or live in separate accounts, each with its own bootstrap.

### New client checklist

- [ ] Project name (`project`), used as the prefix of every resource
- [ ] Region, checked with the dry run from step 2 and, if it is not `us-east-2`, the extra steps above
- [ ] Environments to create and who may deploy to each (the bootstrap creates the deploy role for one environment, `deploy_environment`; each extra environment needs its own role)
- [ ] Budget e-mail addresses and the monthly limit
- [ ] Task size (`task_cpu`, `task_memory`), number of tasks and database size (`db_instance_class`)
- [ ] Production settings: `db_multi_az = true`, `single_nat_gateway = false`, `desired_count` of at least 2
- [ ] Database data: backups, a final snapshot and deletion protection are off by default (see the [database module](../infra/modules/database/README.md)); turn them on before real data arrives
- [ ] The known limitations in the [security review](security-review.md#known-limitations) that must be solved before production: HTTPS with a domain and an ACM certificate, WAF if the app is public, a dedicated database user for the app, VPC endpoints if the client requires that traffic stays inside AWS

### Handover

At the end of the engagement, give the client:

- Access to their copy of the repository
- The state bucket in their own account, with the bootstrap state file (`infra/bootstrap/terraform.tfstate`) handed over, since Terraform needs it to manage the bucket
- This guide and the [security review](security-review.md)
- The commands to deploy (step 7) and to destroy (step 8), and the monthly cost of what is running
- A list of what is left open from the checklist above
- Removal of your own access to their account
