# Security and cost review

Review of the infrastructure in `infra/` and the app image in `app/`, done on 2026-11-15 against the `dev` environment in `us-east-2`.

It covers static analysis of the Terraform code and the container image, a manual review of IAM, security groups and secrets, and the cost of running the environment. Every finding is either fixed or accepted with a reason. Accepted findings are suppressed inline, on the resource, with that reason, so a new finding still fails `make scan`.

## Tools

| Tool | Version | What it checks |
|---|---|---|
| Trivy | 0.76.2 | `trivy config` on `infra/`, `trivy image` on the app image |
| Checkov | 3.4.5 | `checkov -d infra/` |
| Terraform | 1.16.2, AWS provider 6.73.0 | `fmt`, `validate`, plan and apply of `dev` |

Run everything with:

```bash
make scan
```

The scanners run from their official Docker images, pinned to the versions above. The target runs all three and fails if any of them reports a finding that is neither fixed nor suppressed. The image scan fails only on HIGH or CRITICAL vulnerabilities that have a fix available.

## Fixed

| Finding | Fix |
|---|---|
| 2 HIGH CVEs in `zlib1g` (CVE-2026-76844, CVE-2026-85091) with a Debian fix, not yet in the `python:3.12-slim` tag | The final image stage runs `apt-get upgrade`, so a fresh build has every Debian security fix published at build time |
| 6 LOW and MEDIUM CVEs in `pip` 25.0.1 from the base image | `pip` is removed from the final image; the app runs from the virtual environment built by `uv` and never needs it |
| Database client did not verify the server certificate (`sslmode=require`) | The image ships the RDS CA bundle for `us-east-2` (downloaded at build time, checked against a SHA-256) and the task runs with `DB_SSLMODE=verify-full` and `DB_SSLROOTCERT`. Tested: a task that trusts the wrong CA bundle is refused with `certificate verify failed` |
| ALB without access logs (CKV_AWS_91) | Access logs go to a dedicated S3 bucket: public access blocked, SSE-S3, TLS-only policy, 7-day expiration, emptied on destroy |
| VPC without Flow Logs (AWS-0178, CKV2_AWS_11) | Flow Logs for `REJECT` traffic go to CloudWatch Logs with 7-day retention. The flow log role cannot create log groups, so nothing recreates the group after destroy |
| RDS could fall into paid Extended Support when the major version reaches end of support | `engine_lifecycle_support = "open-source-rds-extended-support-disabled"` |
| `rds.force_ssl` showed a change on every plan, because RDS reports it as a static parameter | The parameter group declares `apply_method = "pending-reboot"`. The group is attached when the instance is created, so the first boot already enforces TLS |
| ECR lifecycle counted untagged images against the limit | Untagged images expire after 1 day; the 20 most recent tagged images are kept |
| `make tf-*` targets exported the local `.env` (database credentials) to Terraform | Only `make test` loads `.env` now. Tested with a stub `terraform` that prints its environment |
| `make db-migrate` failure path never exercised | The command can be replaced with `MIGRATE_CMD`; `MIGRATE_CMD=false` makes the target fail with the exit code and the command to read the task log. Tested on AWS |

## Accepted

Trivy severities are shown. The open source Checkov run reports no severity, so Checkov IDs are listed next to the Trivy finding for the same issue, or alone.

| ID | Severity | Resource | Reason |
|---|---|---|---|
| AWS-0054, CKV_AWS_2, CKV_AWS_103, CKV2_AWS_20 | CRITICAL | ALB listener | No domain yet, so there is no certificate for HTTPS. See limitations |
| AWS-0104 | CRITICAL | Task security group, egress 443 to `0.0.0.0/0` | Without VPC endpoints, ECR, CloudWatch Logs and Secrets Manager are reached through the NAT Gateway on their public endpoints. Only port 443 is open |
| AWS-0053 | HIGH | ALB | Public by design: it is the only entry point of the app |
| AWS-0132, CKV_AWS_145 | HIGH | State bucket, access log bucket | SSE-S3 encrypts at rest. A KMS key adds cost and no protection for a single-owner account; ALB access logs support only SSE-S3 |
| CKV_AWS_260 | | ALB security group, port 80 from the internet | Public HTTP is the entry point of the app |
| CKV2_AWS_28 | | ALB | WAF adds about $8 a month (web ACL plus a few managed rule groups) for a demo with no real traffic |
| CKV_AWS_378 | | Target group over HTTP | TLS would end at the ALB; traffic to the tasks stays inside the VPC, in private subnets |
| AWS-0077, CKV_AWS_133 | MEDIUM | RDS backups | A variable, off in the demo so destroy leaves no snapshot. Set 7 days or more for real data |
| AWS-0177, CKV_AWS_293, CKV_AWS_150 | MEDIUM | RDS and ALB deletion protection | A variable, off so the demo can be destroyed |
| AWS-0176, CKV_AWS_161 | MEDIUM | RDS IAM authentication | The app uses the password from Secrets Manager. IAM auth belongs with a dedicated app user (next steps) |
| AWS-0090, CKV_AWS_21 | MEDIUM | Access log bucket versioning | Logs are written once and expire in days; versions would only keep them longer |
| AWS-0089, CKV_AWS_18 | LOW | State bucket, access log bucket | No server access logs: the state has a single owner, and logging the log bucket would need yet another bucket |
| AWS-0133, CKV_AWS_353 | LOW | RDS Performance Insights | Not useful for an environment that lives for minutes |
| AWS-0033, CKV_AWS_136 | LOW | ECR encryption | AES256 at rest; a KMS key adds cost and no protection here |
| AWS-0017, CKV_AWS_158 | LOW | App and Flow Logs log groups | CloudWatch Logs encrypts every log group by default |
| AWS-0034, CKV_AWS_65 | LOW | ECS Container Insights | A variable, off by default because it is billed per metric |
| CKV_AWS_338 | | App and Flow Logs log groups | Retention is a variable; 7 days is enough for a demo |
| CKV_AWS_129, CKV_AWS_118 | | RDS log exports, enhanced monitoring | Both create log groups that RDS owns and that `terraform destroy` would leave behind |
| CKV_AWS_144, CKV2_AWS_62 | | State bucket, access log bucket | No cross-region replica and no event notifications: nothing consumes them, and the state is versioned |
| CKV_AWS_394 | | Availability Zones data source | The module takes the first `az_count` zones, so a new zone does not change the set; pinning names would tie the module to one region |

### Image vulnerabilities without a fix

After the fixes, `trivy image` reports no HIGH or CRITICAL vulnerability with a fix available. These HIGH ones remain, all in Debian 13 packages of the base image, with no fixed version published by Debian at the time of the review:

| CVE | Packages | Why it is accepted |
|---|---|---|
| CVE-2026-76642, CVE-2026-78408, CVE-2026-78409, CVE-2026-78410 | util-linux (`mount`, `login`, `libmount1`, `libblkid1` and others) | Mount and namespace tools. The app never calls them, runs as a non-root user and cannot mount anything on Fargate |
| CVE-2026-16742 | `libsystemd0`, `libudev1` | Affects `systemd-homed`, which does not run in the container |
| CVE-2026-54369 | `libacl1` | Local privilege escalation through symlinks; the root filesystem of the task is read-only |
| CVE-2025-69720 | ncurses | Terminal library; the app has no terminal |
| CVE-2026-119373, CVE-2026-119374, CVE-2026-119379 | `libsqlite3-0` | The app uses PostgreSQL and never opens a SQLite file |
| CVE-2026-9538 | `perl-base` | Archive::Tar; nothing in the app runs Perl |

Once Debian publishes the updates, `make scan` starts failing on them. They are fixed by rebuilding without the layer cache (`docker build --pull --no-cache`), so the `apt-get upgrade` step runs again, and deploying the new image under a new tag.

## IAM

Every role and policy in the Terraform code. The only `*` resource is `ecr:GetAuthorizationToken`, which does not support resource-level permissions.

| Role or policy | Trusted by | Actions | Resources |
|---|---|---|---|
| Task execution role | `ecs-tasks.amazonaws.com` | `ecr:GetAuthorizationToken` | `*` |
| | | `ecr:BatchCheckLayerAvailability`, `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer` | The app repository |
| | | `logs:CreateLogStream`, `logs:PutLogEvents` | The app log group |
| | | `secretsmanager:GetSecretValue` | The database secret only |
| Task role (the app identity) | `ecs-tasks.amazonaws.com`, only from ECS in this account and region (`aws:SourceAccount`, `aws:SourceArn`) | None | None |
| Flow Logs role | `vpc-flow-logs.amazonaws.com`, only for flow logs in this account and region | `logs:CreateLogStream`, `logs:PutLogEvents`, `logs:DescribeLogStreams` | The Flow Logs log group. No `logs:CreateLogGroup` |
| Access log bucket policy | Elastic Load Balancing account of the region | `s3:PutObject` | `AWSLogs/<account-id>/*` in that bucket |
| Access log and state bucket policies | Everyone | Deny `s3:*` without TLS | The bucket and its objects |

## Security groups

Checked on the running environment, not only in the code.

| Security group | Inbound | Outbound |
|---|---|---|
| ALB | TCP 80 from `0.0.0.0/0` | TCP 8000 to the task security group |
| Tasks | TCP 8000 from the ALB security group | TCP 443 to `0.0.0.0/0` (AWS APIs through the NAT); TCP 5432 to the database security group |
| Database | TCP 5432 from the task security group | None |
| VPC default | None | None |

The tasks and the database run in private subnets with no public IP. The database has `publicly_accessible = false` and `rds.force_ssl = 1`.

## Secrets

The only secret is the database master password.

| Where | Result |
|---|---|
| Code and git history | No secret, `.env`, state or `tfvars` file was ever committed. Trivy secret scan of the tree is clean |
| Terraform state | RDS generates the password (`manage_master_user_password`); the state holds only the secret ARN. Checked by searching the live state for the password: 0 matches |
| Task definition | Only the secret ARN and JSON keys, in `secrets`. The ECS agent injects the values at start. 0 matches |
| Container logs | 0 matches in the app log group after migrations, CRUD requests and a failed connection |
| Local `.env` | Holds only the local Postgres password and is no longer exported to Terraform or AWS commands |

## Cost

On-demand prices in `us-east-2`.

| Resource | Per hour | Notes |
|---|---|---|
| NAT Gateway and its Elastic IP | $0.050 | $0.045 + $0.005 for the public IPv4, plus $0.045 per GB processed |
| ALB | $0.041 | $0.0225 + about $0.008 of LCU at demo traffic + 2 public IPv4 addresses |
| Fargate task, 0.25 vCPU and 0.5 GB | $0.012 | |
| RDS `db.t4g.micro`, 20 GB gp3 | $0.019 | Instance $0.016 + storage |
| Secrets Manager secret | $0.001 | $0.40 a month |
| ECR, CloudWatch Logs, Flow Logs, access logs | under $0.01 | A few MB of logs and one image. ALB log delivery is free; S3 storage is cents |
| **`dev` total** | **about $0.12** | About $2.90 a day or $90 a month if left running, which it never is |
| Bootstrap: state bucket and budget | under $0.01 a month | Stays after `make tf-destroy` |

The environment is created, validated and destroyed. This review's run took 28 minutes, about $0.06. Earlier validation runs took between 4 and 21 minutes each.

To check the real cost:

```bash
aws ce get-cost-and-usage --time-period Start=2026-11-12,End=2026-11-17 --granularity DAILY \
  --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE \
  --filter '{"Not":{"Dimensions":{"Key":"RECORD_TYPE","Values":["Credit","Refund"]}}}'
```

Credits are excluded on purpose, because the account's Free Tier credits otherwise net every line to zero. On the day of the review, Cost Explorer showed no charges from the project services for 2026-11-12 to 2026-11-14 and had not yet processed 2026-11-15, the day all validation runs happened.

### NAT Gateway, VPC endpoints and WAF

| Option | Per hour | Per month | Trade-off |
|---|---|---|---|
| One NAT Gateway (current) | $0.050 | $36.50 | Plus $0.045 per GB. One AZ; if it fails, tasks lose access to AWS APIs |
| One NAT Gateway per AZ | $0.100 | $73.00 | Survives an AZ outage |
| No NAT, interface endpoints for ECR API, ECR Docker, CloudWatch Logs and Secrets Manager in 2 AZs, S3 gateway endpoint | $0.080 | $58.40 | Plus $0.01 per GB. Traffic stays off the internet and the 443 egress rule can point at the endpoints, but it costs more than one NAT at this traffic |
| WAF with a web ACL and 3 managed rule groups | $0.011 | about $8 | Plus $0.60 per million requests. Worth it with real users and a domain |

Endpoints pay off when the NAT processes a lot of data or when a client requires that traffic never leave the AWS network.

## Known limitations

- **HTTP only.** There is no domain, so there is no ACM certificate and no HTTPS listener. Traffic between the client and the ALB is not encrypted.
- **Single AZ for the NAT and the database.** One NAT Gateway and a single-AZ RDS instance keep the cost down. Both are one variable away from multi-AZ (`single_nat_gateway`, `db_multi_az`).
- **No WAF.**
- **No VPC endpoints.** AWS API traffic leaves through the NAT Gateway over TLS.
- **The app connects as the RDS master user.** A dedicated user with only the privileges the app needs is not set up yet.
- **Password rotation needs a redeploy.** RDS rotates the master password every 7 days. ECS injects it only when a task starts, so after a rotation the running tasks must be replaced.
- **The CA bundle is for `us-east-2`.** The `region` variable of `dev` accepts only `us-east-2` until the bundle in `app/Dockerfile` is changed.
- **Demo defaults on data.** No backups, no final snapshot and no deletion protection, so `make tf-destroy` leaves nothing behind.

## Next steps

1. Domain, ACM certificate, HTTPS listener and a redirect from port 80.
2. A dedicated database user for the app, with IAM authentication or a secret that the app reads at runtime, so rotation needs no redeploy.
3. WAF with the AWS managed rule groups once there is real traffic.
4. VPC endpoints when NAT data processing or a compliance requirement justifies them.
5. `make scan` in CI on every pull request.
