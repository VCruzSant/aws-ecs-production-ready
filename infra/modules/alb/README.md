# Module: alb

A public Application Load Balancer in the public subnets, in front of ECS tasks in the private subnets.

- **Security group.** Inbound only `80/tcp` from the internet. Outbound only to the security group of the app tasks, on the app port. The load balancer cannot open connections anywhere else.
- **Target group.** Type `ip`, as required by Fargate (`awsvpc` networking). Health check on `/health` expecting `200`, every 10 seconds; 2 successes mark a task healthy and 3 failures unhealthy, so a broken task leaves rotation in about 30 seconds.
- **Deregistration delay** of 30 seconds instead of the default 300, which keeps deployments and `destroy` fast for a small API with short requests.
- **`drop_invalid_header_fields`** is on, so malformed HTTP headers never reach the app.
- **HTTP listener** on port 80 forwarding to the target group.

There is no HTTPS listener because the project has no domain yet. For production, add an ACM certificate, a `443` listener and a redirect from `80` to `443`.

The `target_group_arn` output depends on the listener, because ECS rejects a target group that is not attached to a load balancer yet.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | (required) | Name of the load balancer and target group (up to 32 characters) and prefix of the security group |
| `vpc_id` | `string` | (required) | ID of the VPC |
| `public_subnet_ids` | `list(string)` | (required) | Public subnets, in at least two AZs |
| `app_security_group_id` | `string` | (required) | Security group of the app tasks, the only egress destination |
| `app_port` | `number` | `8000` | Port the app listens on |
| `health_check_path` | `string` | `"/health"` | Health check path |
| `deregistration_delay` | `number` | `30` | Seconds to drain a task before it is removed |
| `enable_deletion_protection` | `bool` | `false` | Block deletion of the load balancer |
| `tags` | `map(string)` | `{}` | Extra tags merged into every resource |

## Outputs

| Name | Description |
|---|---|
| `dns_name` | Public DNS name of the load balancer |
| `arn_suffix` | ARN suffix of the load balancer, for CloudWatch metrics |
| `security_group_id` | Security group of the load balancer |
| `target_group_arn` | Target group for the ECS service |
| `target_group_arn_suffix` | ARN suffix of the target group, for CloudWatch metrics |

## Usage

```hcl
module "alb" {
  source = "../../modules/alb"

  name                  = "my-app-dev"
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  app_port              = 8000
  app_security_group_id = module.ecs_service.security_group_id
}
```

The ALB and the ECS service reference each other's security groups. That is fine in Terraform because the rules are separate resources, so there is no dependency cycle.

Requires Terraform `>= 1.10` and the AWS provider `~> 6.73`.
