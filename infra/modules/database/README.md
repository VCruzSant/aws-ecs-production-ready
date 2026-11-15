# Module: database

A PostgreSQL instance on RDS in the private subnets, reachable only from the app tasks.

- **Engine.** PostgreSQL 16 by default, the same major as the local `docker compose` stack. With a major-only `engine_version`, RDS picks the current minor and applies minor upgrades in the maintenance window.
- **Instance.** `db.t4g.micro` (2 vCPU burstable, 1 GB, Graviton) with 20 GB of encrypted `gp3` storage.
- **Network.** DB subnet group on the private subnets, `publicly_accessible = false`. The security group accepts only the database port from the app security group and has no other rules.
- **Password.** `manage_master_user_password = true`: RDS generates the master password and stores it in a Secrets Manager secret it owns (JSON keys `username` and `password`). The password is never in the Terraform code, the plan or the state. Only the secret ARN is exported, for ECS to inject the values when a task starts.
- **TLS.** A dedicated parameter group sets `rds.force_ssl = 1`, so the server refuses unencrypted connections. Clients should use at least `sslmode=require`. That encrypts the traffic but does not check the server certificate; `verify-full` with the RDS CA bundle does.

## Demo defaults

These defaults keep a create, validate and destroy cycle fast and free of leftovers. Change them for anything that holds real data.

| Variable | Default | Why | For production |
|---|---|---|---|
| `multi_az` | `false` | A standby doubles the instance cost | `true` |
| `backup_retention_period` | `0` | No automated backups, so no automated snapshot is left behind after the instance is deleted; it also makes creation faster | 7 or more |
| `skip_final_snapshot` | `true` | A final snapshot would outlive `terraform destroy` and keep costing money | `false` (the snapshot is named `<name>-final`) |
| `deletion_protection` | `false` | `terraform destroy` must be able to remove the instance | `true` |
| `apply_immediately` | `true` | Changes apply now instead of waiting for the maintenance window | `false` |

The secret created by RDS is deleted together with the instance.

RDS rotates the master password every 7 days by default. ECS injects it only when a task starts, so after a rotation running tasks fail to open new connections until they are replaced (`aws ecs update-service --force-new-deployment`). A short-lived demo never reaches the first rotation; a long-running environment should use a dedicated app user or redeploy on rotation.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | (required) | Identifier of the instance and subnet group; prefix of the security group and parameter group |
| `vpc_id` | `string` | (required) | ID of the VPC |
| `private_subnet_ids` | `list(string)` | (required) | Private subnets, in at least two AZs |
| `app_security_group_id` | `string` | (required) | Security group of the app, the only allowed source |
| `engine_version` | `string` | `"16"` | Postgres version |
| `instance_class` | `string` | `"db.t4g.micro"` | Instance class |
| `allocated_storage` | `number` | `20` | Storage in GiB |
| `db_name` | `string` | `"demo"` | Database created with the instance |
| `username` | `string` | `"demo"` | Master username |
| `port` | `number` | `5432` | Port |
| `multi_az` | `bool` | `false` | Standby in a second AZ |
| `backup_retention_period` | `number` | `0` | Days of automated backups |
| `skip_final_snapshot` | `bool` | `true` | Delete without a final snapshot |
| `deletion_protection` | `bool` | `false` | Block deletion |
| `apply_immediately` | `bool` | `true` | Apply changes outside the maintenance window |
| `tags` | `map(string)` | `{}` | Extra tags merged into every resource |

## Outputs

| Name | Description |
|---|---|
| `address` | Hostname of the instance |
| `port` | Port of the instance |
| `db_name` | Name of the database |
| `master_user_secret_arn` | ARN of the Secrets Manager secret with the master credentials |
| `security_group_id` | Security group of the instance |

## Usage

```hcl
module "database" {
  source = "../../modules/database"

  name                  = "my-app-dev"
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  app_security_group_id = module.ecs_service.security_group_id
}
```

Pair it with the `ecs-service` inputs `secrets` and `egress_security_groups`, as `envs/dev` does.

Requires Terraform `>= 1.10` and the AWS provider `~> 6.73`.
