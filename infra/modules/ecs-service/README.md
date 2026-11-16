# Module: ecs-service

One containerized app on ECS Fargate, registered in an existing ALB target group.

What it creates:

- **Cluster** with Container Insights off by default (it adds cost per metric; turn it on with `container_insights = true`). When on, the module also creates the Container Insights log group `/aws/ecs/containerinsights/<name>/performance`, so it is removed on destroy instead of being created by AWS and left behind.
- **Task definition** for Fargate, `LINUX/X86_64`, 0.25 vCPU and 0.5 GB by default. The container runs with a read-only root filesystem and sends its stdout to CloudWatch Logs.
- **Log group** `/ecs/<name>` with 7 days of retention.
- **Execution role**, used by the ECS agent to start the task: pull from the given ECR repository, write to the log group and, `secretsmanager:GetSecretValue` on the secrets referenced in `secrets` only. Nothing else.
- **Task role**, the identity of the app code. It has no permissions yet; add them only when the app calls an AWS API.
- **Security group** for the tasks. Inbound only the app port from the load balancer security group. Outbound HTTPS through the NAT Gateway (ECR, CloudWatch Logs, Secrets Manager), plus one rule per entry in `egress_security_groups`, each limited to one port and one security group (the database, in `envs/dev`).
- **Service** in private subnets with no public IP, `desired_count` tasks, rolling deployments (100% minimum, 200% maximum) and the **deployment circuit breaker with rollback**: if new tasks never become healthy, ECS stops the deployment and goes back to the last working task definition.

**Secrets** never go in `environment`. `secrets` maps an environment variable to a Secrets Manager reference (`<secret-arn>:<json-key>::`); ECS reads the value when the task starts, so the task definition holds only the ARN. The execution role gets read access to exactly those secrets, taken from the references.

`health_check_grace_period_seconds` defaults to 30: the demo API answers `/health` a few seconds after the container starts, and the grace period keeps ECS from killing a task that is still booting.

`terraform apply` waits for the service to reach a steady state (`wait_for_steady_state`), so a failed deployment fails the apply instead of passing silently.

The service ignores changes to `task_definition`. Terraform sets the first revision and the deploy pipeline rolls out the next ones, so a `plan` after a pipeline deploy does not switch the service back. A Terraform change to the task definition (CPU, memory, environment) registers a new revision of the family, and the next pipeline deploy starts from it.

`image` may be null only while the module is not being created or updated (for example on `terraform destroy`); a precondition on the task definition stops any other plan without it.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | (required) | Name of the cluster, service and task family; prefix of the roles, security group and log group |
| `vpc_id` | `string` | (required) | ID of the VPC |
| `private_subnet_ids` | `list(string)` | (required) | Private subnets for the tasks |
| `alb_security_group_id` | `string` | (required) | Security group of the load balancer, the only inbound source |
| `target_group_arn` | `string` | (required) | Target group the tasks register in |
| `ecr_repository_arn` | `string` | (required) | Repository the execution role can pull from |
| `image` | `string` | `null` | Full image reference with an immutable tag (not `latest`) |
| `container_name` | `string` | `"app"` | Container name in the task definition |
| `container_port` | `number` | `8000` | Port the app listens on |
| `environment` | `map(string)` | `{}` | Plain environment variables (no secrets) |
| `secrets` | `map(string)` | `{}` | Env vars filled from Secrets Manager: variable name to `<secret-arn>:<json-key>::` |
| `egress_security_groups` | `map(object({ port = number, security_group_id = string }))` | `{}` | Extra outbound TCP access to other security groups |
| `cpu` | `number` | `256` | Task CPU units |
| `memory` | `number` | `512` | Task memory in MiB |
| `desired_count` | `number` | `1` | Number of tasks |
| `health_check_grace_period_seconds` | `number` | `30` | Seconds to ignore failing health checks after a task starts |
| `container_insights` | `bool` | `false` | Enable Container Insights and create its log group |
| `log_retention_days` | `number` | `7` | Log retention in days |
| `wait_for_steady_state` | `bool` | `true` | Make apply wait for healthy tasks |
| `tags` | `map(string)` | `{}` | Extra tags merged into every resource |

## Outputs

| Name | Description |
|---|---|
| `cluster_name` | Name of the cluster |
| `cluster_arn` | ARN of the cluster |
| `service_name` | Name of the service |
| `task_definition_arn` | ARN of the current task definition revision |
| `container_name` | Name of the container (for task overrides, e.g. `make db-migrate`) |
| `security_group_id` | Security group of the tasks |
| `log_group_name` | CloudWatch log group |
| `execution_role_arn` | ARN of the execution role |
| `task_role_arn` | ARN of the task role |

## Usage

```hcl
module "ecs_service" {
  source = "../../modules/ecs-service"

  name                  = "my-app-dev"
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.target_group_arn
  ecr_repository_arn    = module.ecr.repository_arn

  image = "${module.ecr.repository_url}:abc1234"
}
```

Requires Terraform `>= 1.10` and the AWS provider `~> 6.73`.
