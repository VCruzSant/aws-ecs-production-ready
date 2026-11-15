# Infrastructure

Terraform for the AWS side of the project, in `us-east-2` (set through the `region` variable; same prices as `us-east-1` for everything used here). Everything is written from scratch (no third-party modules).

| Path | What it is |
|---|---|
| `bootstrap/` | One-time stack with **local** state: the S3 bucket that stores the remote state of every environment, and a monthly AWS Budget with e-mail alerts. It is not destroyed with the environments. |
| `modules/network/` | Reusable VPC module: public and private subnets across 2 AZs, Internet Gateway, NAT Gateway(s). See its [README](modules/network/README.md). |
| `envs/dev/` | The `dev` environment. Remote state in S3 with native locking (`use_lockfile`, no DynamoDB table). Today it creates the network; ECS, ALB and RDS come next. |

## Requirements

- Terraform `>= 1.10` (native S3 state locking) and the AWS CLI v2
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
make tf-plan                                   # init with backend.hcl + plan into tfplan
terraform -chdir=infra/envs/dev apply tfplan   # after reviewing the plan
make tf-destroy                                # when done: removes everything in dev
```

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
| `dev` with `single_nat_gateway = false` | ~$0.10/hour | One NAT + Elastic IP per AZ |
| Bootstrap: state bucket | **< $0.01/month** | A few KB of state files plus a handful of requests |
| Bootstrap: AWS Budget | **$0** | The first two budgets in an account are free |

**What stays after `make tf-destroy`:** only the bootstrap (state bucket + budget), at a few cents per month at most.
