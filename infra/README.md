# Infrastructure

Terraform for the AWS side of the project, in `us-east-2` (set through the `region` variable; same prices as `us-east-1` for everything used here). Everything is written from scratch (no third-party modules).

| Path | What it is |
|---|---|
| `bootstrap/` | One-time stack with **local** state: the S3 bucket that stores the remote state of every environment, and a monthly AWS Budget with e-mail alerts. It is not destroyed with the environments. |
| `modules/network/` | Reusable VPC module: public and private subnets across 2 AZs, Internet Gateway, NAT Gateway(s). See its [README](modules/network/README.md). |
| `modules/ecr/` | Private image repository with immutable tags, scan on push and a lifecycle policy. See its [README](modules/ecr/README.md). |
| `modules/alb/` | Public Application Load Balancer, target group for ECS tasks and HTTP listener. See its [README](modules/alb/README.md). |
| `modules/ecs-service/` | ECS cluster, Fargate task definition, service with circuit breaker rollback, IAM roles, logs. See its [README](modules/ecs-service/README.md). |
| `modules/database/` | PostgreSQL on RDS in the private subnets, password managed by RDS in Secrets Manager, TLS required. See its [README](modules/database/README.md). |
| `envs/dev/` | The `dev` environment: network, ECR, ALB, the app on ECS Fargate and its RDS database. Remote state in S3 with native locking (`use_lockfile`, no DynamoDB table). |

## Requirements

- Terraform `>= 1.10` (native S3 state locking), the AWS CLI v2 and Docker (to build and push the image)
- An AWS CLI profile for the target account, exported before running anything:

```bash
export AWS_PROFILE=<your-profile>
aws sts get-caller-identity   # make sure this is the account you expect
```

No credentials, account IDs or e-mails are stored in versioned files.

## Usage

### 1. Bootstrap (once per account)

```bash
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars   # set budget_alert_emails
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output -raw state_bucket_name
```

The budget e-mails the listed addresses directly (no subscription to confirm) at 50% and 100% of the actual monthly spend and at 100% of the forecast.

The bootstrap state (`terraform.tfstate`) stays on your machine and is git-ignored. Keep it: it is the only record Terraform has of the bucket and the budget. The bucket has `prevent_destroy`, so removing it requires editing the code on purpose.

### 2. Dev environment

```bash
cd infra/envs/dev
cp backend.hcl.example backend.hcl             # set bucket and region from the bootstrap outputs
cp terraform.tfvars.example terraform.tfvars   # optional, defaults are fine
cd ../../..
```

First deploy, from an empty environment:

```bash
make infra-up
```

It runs four steps:

1. `terraform apply -target=module.ecr` creates only the ECR repository (asks for confirmation).
2. `make image-push` builds `app/` for `linux/amd64`, tags it with the short SHA of the last commit that changed `app/` and pushes it to ECR.
3. `terraform apply -var image_tag=<sha>` shows the plan for everything else and asks for confirmation. Creating the RDS instance takes about 10 minutes.
4. `make db-migrate` runs the database migrations (see below).

The ECS service needs an image that does not exist until the repository exists, so the first deploy has to create the repository on its own. This is the only place where `-target` is used. Once the repository is there, every change goes through a normal plan:

```bash
make image-push                                # skipped if that tag is already in ECR
make tf-plan                                   # plan with IMAGE_TAG (defaults to the same SHA)
terraform -chdir=infra/envs/dev apply tfplan
make db-migrate                                # when the release has new migrations; a no-op otherwise
```

Commits that only touch `infra/` or docs keep the same tag, so they reuse the image already in ECR. The tag gets a `-dirty` suffix when `app/` has uncommitted or untracked changes. Tags are immutable: ECR refuses a different image under an existing tag. Pass `IMAGE_TAG=<tag>` to both targets to choose one; `latest` is rejected.

`terraform apply` waits until the service is stable. If the new tasks never pass the load balancer health check, the deployment circuit breaker stops it and rolls back to the previous task definition.

### Database migrations

`make db-migrate` starts a one-off ECS task with the current task definition of the service, in the private subnets and with the app security group, and replaces the container command with `alembic upgrade head`. It waits for the task to stop, prints its log and fails unless the exit code is 0. Running it again is safe: Alembic skips migrations that are already applied.

The migration is not part of the container command on purpose. Every task of the service runs that command, so during a deployment or a scale-out several tasks would start the same migration at the same time. A single task, run once per release, keeps schema changes in one place and makes a failed migration stop the release instead of crash-looping the service.

The target runs the task definition the service is currently using (read from ECS, not from the Terraform state), so after a circuit breaker rollback it migrates with the code that is actually live.

Until the first migration runs, `/health` is 200 but `/tasks` fails because the table does not exist yet.

The migration runs after `terraform apply`, so for a short time the new code runs against the old schema. Keep migrations backward compatible (add columns before using them, drop them a release later). Running the migration before the service is updated belongs in the CD pipeline.

### Database credentials

RDS generates the master password and keeps it in a Secrets Manager secret (`manage_master_user_password`). It never appears in the code, the plan, the state or the task definition. The task definition references the secret keys `username` and `password` as `secrets`, and the ECS agent injects them as `DB_USER` and `DB_PASSWORD` when the task starts. The execution role can call `secretsmanager:GetSecretValue` on that one secret only.

The app connects with `DB_SSLMODE=require`, and the parameter group sets `rds.force_ssl = 1`, so traffic to the database is always encrypted. The client does not verify the server certificate yet (`verify-full` with the RDS CA bundle is the next step).

### Check the deployment

```bash
URL=$(terraform -chdir=infra/envs/dev output -raw alb_url)
curl -i "$URL/health"                                                              # 200 {"status":"ok"}
curl -i "$URL/health/db"                                                           # 200 {"status":"ok"}
curl -i -X POST "$URL/tasks" -H 'Content-Type: application/json' -d '{"title":"first"}'   # 201
aws logs tail "$(terraform -chdir=infra/envs/dev output -raw log_group_name)" --since 10m
```

When done:

```bash
make tf-destroy                                # removes everything in dev, ECR images, logs, database and its secret included
```

The database runs with demo settings: single-AZ, no automated backups, no final snapshot on destroy and no deletion protection. Everything in it is lost on `make tf-destroy`. The [module README](modules/database/README.md) lists what to change for real data.

The app is served over plain HTTP on the load balancer DNS name. There is no domain yet; the next step for a real deployment is a Route 53 record, an ACM certificate and an HTTPS listener that redirects port 80.

### Checks (no AWS credentials needed)

```bash
make tf-fmt        # terraform fmt -recursive -check infra
make tf-validate   # init without backend + validate, for bootstrap and dev
```

## Cost (us-east-2, on-demand prices)

The environments are meant to be created, validated and destroyed, not left running.

| What | While running | Notes |
|---|---|---|
| `dev` network (1 NAT Gateway + 1 Elastic IP) | **~$0.05/hour** (~$1.20/day) | NAT $0.045/h + public IPv4 $0.005/h, plus $0.045/GB processed by the NAT. VPC, subnets, route tables and Internet Gateway are free. |
| `dev` app: ALB | ~$0.04/hour | $0.0225/h + about $0.008/h of LCU at demo traffic + 2 public IPv4 addresses (one per AZ) at $0.005/h each |
| `dev` app: one Fargate task (0.25 vCPU, 0.5 GB, x86) | ~$0.012/hour | $0.04048 per vCPU-hour + $0.004445 per GB-hour |
| `dev` database: RDS `db.t4g.micro`, single-AZ | ~$0.02/hour | Instance $0.016/h + 20 GB gp3 at $0.115/GB-month (~$0.003/h) + the Secrets Manager secret at $0.40/month (~$0.001/h). |
| `dev` app: ECR and CloudWatch Logs | < $0.01/day | Under 100 MB per compressed image at $0.10/GB-month; a few KB of logs |
| **`dev` total** | **~$0.12/hour** (~$2.90/day) | Network + ALB + one task + database |
| `dev` with `single_nat_gateway = false` | +$0.05/hour | One more NAT + Elastic IP |
| `dev` with `db_multi_az = true` | +$0.02/hour | Standby instance and its storage |
| Bootstrap: state bucket | **< $0.01/month** | A few KB of state files plus a handful of requests |
| Bootstrap: AWS Budget | **$0** | The first two budgets in an account are free |

**What stays after `make tf-destroy`:** only the bootstrap (state bucket + budget), at a few cents per month at most.
