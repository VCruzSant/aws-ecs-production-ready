# Infrastructure

Terraform for the AWS side of the project. The region defaults to `us-east-2` and is set through the `region` variable. Everything is written from scratch (no third-party modules).

| Path | What it is |
|---|---|
| `bootstrap/` | One-time stack with **local** state: the S3 bucket that stores the remote state of every environment, a monthly AWS Budget with e-mail alerts and, when `github_repository` is set, the GitHub OIDC provider and the deploy role. It is not destroyed with the environments. See its [README](bootstrap/README.md). |
| `modules/network/` | Reusable VPC module: public and private subnets across 2 AZs, Internet Gateway, NAT Gateway(s), VPC Flow Logs for rejected traffic. See its [README](modules/network/README.md). |
| `modules/ecr/` | Private image repository with immutable tags, scan on push and a lifecycle policy. See its [README](modules/ecr/README.md). |
| `modules/alb/` | Public Application Load Balancer, target group for ECS tasks, HTTP listener and access logs in S3. See its [README](modules/alb/README.md). |
| `modules/ecs-service/` | ECS cluster, Fargate task definition, service with circuit breaker rollback, IAM roles, logs. See its [README](modules/ecs-service/README.md). |
| `modules/database/` | PostgreSQL on RDS in the private subnets, password managed by RDS in Secrets Manager, TLS required. See its [README](modules/database/README.md). |
| `modules/monitoring/` | SNS topic with e-mail subscriptions and ten CloudWatch alarms for the ALB, the ECS service and the database. See its [README](modules/monitoring/README.md). |
| `envs/dev/` | The `dev` environment, also the template for new ones (copy the folder, see the guide): network, ECR, ALB, the app on ECS Fargate, its RDS database and the alarms. Remote state in S3 with native locking (`use_lockfile`, no DynamoDB table). |

## Requirements

- Terraform `>= 1.10` (native S3 state locking), the AWS CLI v2 and Docker (to build and push the image)
- An AWS CLI profile for the target account, exported before running anything (see the [provisioning guide](../docs/provisioning-guide.md) for the prerequisites):

```bash
export AWS_PROFILE=<your-profile>
aws sts get-caller-identity   # make sure this is the account you expect
```

No credentials, account IDs or e-mails are stored in versioned files.

## Usage

The step-by-step guide, from prerequisites to destroy and including how to use this for a new client, is in the [provisioning guide](../docs/provisioning-guide.md). The short version, with `ENV` as the folder name under `envs/` (default `dev`):

```bash
make infra-up ENV=dev       # first deploy: ECR, image, everything else, migration
make tf-plan ENV=dev        # later changes: review, then terraform -chdir=infra/envs/dev apply tfplan
make tf-destroy ENV=dev     # remove the environment
```

The ECS service needs an image that does not exist until the repository exists, so the first deploy creates the repository on its own with `-target=module.ecr`. This is the only place where `-target` is used. Commits that only touch `infra/` or docs keep the same image tag, so they reuse the image already in ECR. Tags are immutable: ECR refuses a different image under an existing tag. Pass `IMAGE_TAG=<tag>` to choose one; `latest` is rejected.

`terraform apply` waits until the service is stable. If the new tasks never pass the load balancer health check, the deployment circuit breaker stops it and rolls back to the previous task definition.

### Database migrations

`make db-migrate` starts a one-off ECS task with the current task definition of the service, in the private subnets and with the app security group, and replaces the container command with `alembic upgrade head`. It waits for the task to stop, prints its log and fails unless the exit code is 0, showing the exit code and the command to read the task log. Running it again is safe: Alembic skips migrations that are already applied.

`MIGRATE_CMD` replaces the command, for example `make db-migrate MIGRATE_CMD="alembic downgrade -1"`. It takes plain words only: they are split on spaces, and quotes, backslashes or `$` are rejected. `MIGRATE_CMD=false` exercises the failure path.

The migration is not part of the container command on purpose. Every task of the service runs that command, so during a deployment or a scale-out several tasks would start the same migration at the same time. A single task, run once per release, keeps schema changes in one place and makes a failed migration stop the release instead of crash-looping the service.

The target runs the task definition the service is currently using (read from ECS, not from the Terraform state), so after a circuit breaker rollback it migrates with the code that is actually live.

Until the first migration runs, `/health` is 200 but `/tasks` fails because the table does not exist yet.

With `make infra-up` the migration runs after `terraform apply`, so for a short time the new code runs against the old schema. The deploy workflow runs it before the service is updated, so the old code runs against the new schema instead. Either way, keep migrations backward compatible (add columns before using them, drop them a release later).

The logic lives in `scripts/ecs-migrate.sh`, shared by `make db-migrate` and the deploy workflow. It reads the subnets, security group, container and log group from the service and the task definition, so it needs no Terraform output.

### Who owns what

Terraform creates and changes the infrastructure. The deploy workflow (`.github/workflows/deploy.yml`) changes the image.

- `make infra-up` sets the first task definition revision. After that, the service ignores `task_definition` in Terraform (`ignore_changes`), so a `plan` after a pipeline deploy does not switch the service back to an older image.
- Each deploy registers a new revision from the latest one of the family, with only the image replaced. A Terraform change to the task definition (CPU, memory, environment) registers a revision that reaches the service on the next deploy. To ship it without a new image, run the workflow by hand: the image tag already exists, so only the revision changes.
- The pipeline never runs Terraform. Infrastructure changes still go through `make tf-plan` and `apply`.

### Continuous deployment

A push to `main` that changes `app/`, or a manual run with an optional ref, starts the deploy workflow in the GitHub environment `dev`:

1. It assumes the deploy role through OIDC. There is no AWS key in GitHub.
2. If the service does not exist or is not `ACTIVE`, it writes "No environment running, skipping deploy" to the job summary and ends green. This is the normal state, since the environment only runs while it is being validated.
3. It builds the image and pushes it with the short SHA of the last commit that changed `app/` as the tag, unless that tag is already in ECR.
4. It registers a new task definition revision with that image, runs `alembic upgrade head` with it as a one-off task and stops if the exit code is not 0.
5. It updates the service and follows the deployment. If the circuit breaker rolls back, the job fails with the revision it went back to.
6. The job summary shows the image tag, the new, previous and running revisions and the result.

`/health` returns the image tag as `version`, so `curl $URL/health` shows which commit is serving.

The [provisioning guide](../docs/provisioning-guide.md#11-continuous-deployment) lists the GitHub environment variables.

### Database credentials

RDS generates the master password and keeps it in a Secrets Manager secret (`manage_master_user_password`). It never appears in the code, the plan, the state or the task definition. The task definition references the secret keys `username` and `password` as `secrets`, and the ECS agent injects them as `DB_USER` and `DB_PASSWORD` when the task starts. The execution role can call `secretsmanager:GetSecretValue` on that one secret only.

The parameter group sets `rds.force_ssl = 1`, so the database refuses unencrypted connections. The app connects with `DB_SSLMODE=verify-full` and `DB_SSLROOTCERT=/etc/ssl/certs/rds-ca.pem`: the image ships the RDS CA bundle of the region (downloaded at build time and checked against a SHA-256), and the client verifies both the certificate chain and the hostname. The Dockerfile defaults to `us-east-2`; for another region pass `RDS_CA_SHA256` to `make image-push` as the [provisioning guide](../docs/provisioning-guide.md#using-another-region) explains.

### Alarms

Ten alarms send an e-mail through SNS when they go to `ALARM` and again when they return to `OK`. Set `alert_emails` in `terraform.tfvars` and confirm the subscription e-mail AWS sends after the apply; until then nothing is delivered. Names are `<project>-<env>-<resource>-<metric>`; each alarm description says what to check.

| Alarm | Fires when | First thing to check |
|---|---|---|
| `alb-healthy-hosts` | No healthy target for 2 minutes, or no data | `aws ecs describe-services` events and the app logs |
| `alb-target-5xx` | More than 5 app 5xx responses per minute for 2 minutes | App logs |
| `alb-elb-5xx` | More than 5 load balancer 5xx responses per minute for 2 minutes | Target health |
| `alb-response-time-p95` | p95 above 1 second for 2 minutes | Task CPU and the database |
| `ecs-cpu`, `ecs-memory` | Average above 80% for 2 minutes | Scale out or raise the task size |
| `ecs-running-tasks` | Fewer running tasks than `desired_count`, or no data (Container Insights) | Stopped tasks and their stop reason |
| `rds-cpu` | Average above 80% for 2 minutes | Slow queries, instance size |
| `rds-free-storage` | Under 2 GiB free | Raise `allocated_storage` |
| `rds-freeable-memory` | Under 64 MiB freeable | Connections, instance size |

A missing metric counts as a problem for `alb-healthy-hosts` and `ecs-running-tasks`. CloudWatch only notices a metric that stopped after a few minutes: scaling the service to 0 raised `ecs-running-tasks` after 7.5 minutes and `alb-healthy-hosts` after 9 minutes, so expect that delay, not one minute.

Container Insights is on in `dev` (`container_insights = true`) and its log group is created by Terraform so `make tf-destroy` removes it. The topic is not encrypted with KMS, see the [security review](../docs/security-review.md).

### Check the deployment

```bash
URL=$(terraform -chdir=infra/envs/dev output -raw alb_url)
curl -i "$URL/health"                                                              # 200 {"status":"ok","version":"<tag>"}
curl -i "$URL/health/db"                                                           # 200 {"status":"ok"}
curl -i -X POST "$URL/tasks" -H 'Content-Type: application/json' -d '{"title":"first"}'   # 201
aws logs tail "$(terraform -chdir=infra/envs/dev output -raw log_group_name)" --since 10m
aws s3 ls "s3://$(terraform -chdir=infra/envs/dev output -raw alb_access_logs_bucket)" --recursive   # access logs, every 5 minutes
aws logs tail "$(terraform -chdir=infra/envs/dev output -raw flow_logs_log_group_name)" --since 10m  # rejected traffic
```

When done:

```bash
make tf-destroy                                # removes everything in dev, ECR images, logs, access log bucket, database and its secret included
```

The database runs with demo settings: single-AZ, no automated backups, no final snapshot on destroy and no deletion protection. Everything in it is lost on `make tf-destroy`. The [module README](modules/database/README.md) lists what to change for real data.

The app is served over plain HTTP on the load balancer DNS name. There is no domain yet; the next step for a real deployment is a Route 53 record, an ACM certificate and an HTTPS listener that redirects port 80.

### Checks (no AWS credentials needed)

```bash
make tf-fmt        # terraform fmt -recursive -check infra
make tf-validate   # init without backend + validate, for bootstrap and dev
make scan          # trivy and checkov on infra/, trivy on the app image (needs Docker, no AWS)
```

`make scan` fails on any finding that is neither fixed nor suppressed inline with a reason. The decisions are in the [security and cost review](../docs/security-review.md).

The Terraform targets do not read `.env`; only `make test` loads it.

## Cost (us-east-2, on-demand prices)

The environments are meant to be created, validated and destroyed, not left running.

| What | While running | Notes |
|---|---|---|
| `dev` network (1 NAT Gateway + 1 Elastic IP) | **~$0.05/hour** (~$1.20/day) | NAT $0.045/h + public IPv4 $0.005/h, plus $0.045/GB processed by the NAT. VPC, subnets, route tables and Internet Gateway are free. |
| `dev` app: ALB | ~$0.04/hour | $0.0225/h + about $0.008/h of LCU at demo traffic + 2 public IPv4 addresses (one per AZ) at $0.005/h each |
| `dev` app: one Fargate task (0.25 vCPU, 0.5 GB, x86) | ~$0.012/hour | $0.04048 per vCPU-hour + $0.004445 per GB-hour |
| `dev` database: RDS `db.t4g.micro`, single-AZ | ~$0.02/hour | Instance $0.016/h + 20 GB gp3 at $0.115/GB-month (~$0.003/h) + the Secrets Manager secret at $0.40/month (~$0.001/h). |
| `dev` app: ECR and CloudWatch Logs | < $0.01/day | Under 100 MB per compressed image at $0.10/GB-month; a few KB of logs |
| `dev` Flow Logs and ALB access logs | < $0.01/day | $0.50/GB ingested by CloudWatch Logs for rejected traffic (a few MB); ALB log delivery is free and S3 storage for 7 days is cents |
| `dev` Container Insights and alarms | ~$0.01/hour | Container Insights custom metrics and its logs, plus 10 standard alarms at $0.10/month each. SNS e-mail is free for the first 1,000 notifications |
| **`dev` total** | **~$0.13/hour** (~$3.10/day) | Network + ALB + one task + database + monitoring |
| `dev` with `single_nat_gateway = false` | +$0.05/hour | One more NAT + Elastic IP |
| `dev` with `db_multi_az = true` | +$0.02/hour | Standby instance and its storage |
| Bootstrap: state bucket | **< $0.01/month** | A few KB of state files plus a handful of requests |
| Bootstrap: AWS Budget | **$0** | The first two budgets in an account are free |
| Bootstrap: GitHub OIDC provider and deploy role | **$0** | IAM is free |

**What stays after `make tf-destroy`:** only the bootstrap (state bucket, budget, OIDC provider and deploy role), at a few cents per month at most.
