# Module: monitoring

An SNS topic with e-mail subscriptions and CloudWatch alarms for one environment: the ALB and target group, the ECS service and the RDS instance.

Every alarm sends to the topic on `ALARM` and on `OK`. The topic policy lets only CloudWatch publish, and only for alarms of this account named `<name>-*`.

The topic has no KMS key: CloudWatch cannot publish to a topic encrypted with `aws/sns`, and a customer managed key is billed and lingers after destroy. See the security review.

Each address in `alert_emails` receives a confirmation e-mail after the apply. Nothing is delivered until it is confirmed.

`RunningTaskCount` comes from Container Insights, so the cluster needs `container_insights = true`. With no data, `HealthyHostCount` and `RunningTaskCount` count as breaching; the other alarms treat no data as fine.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | (required) | Prefix of the topic and the alarms |
| `alert_emails` | `list(string)` | (required) | Subscribed e-mail addresses |
| `alb_arn_suffix` | `string` | (required) | ARN suffix of the load balancer |
| `target_group_arn_suffix` | `string` | (required) | ARN suffix of the target group |
| `cluster_name` | `string` | (required) | ECS cluster name |
| `service_name` | `string` | (required) | ECS service name |
| `desired_count` | `number` | (required) | Tasks expected to run |
| `db_instance_identifier` | `string` | (required) | RDS instance identifier |
| `period_seconds` | `number` | `60` | Evaluation period |
| `evaluation_periods` | `number` | `2` | Breaching periods before an alarm fires |
| `cpu_threshold_percent` | `number` | `80` | ECS and RDS CPU threshold |
| `memory_threshold_percent` | `number` | `80` | ECS memory threshold |
| `target_5xx_threshold` | `number` | `5` | App 5xx per period |
| `elb_5xx_threshold` | `number` | `5` | Load balancer 5xx per period |
| `response_time_p95_seconds` | `number` | `1` | p95 response time |
| `db_free_storage_bytes` | `number` | `2147483648` | Minimum free storage |
| `db_freeable_memory_bytes` | `number` | `67108864` | Minimum freeable memory |
| `tags` | `map(string)` | `{}` | Extra tags |

## Outputs

| Name | Description |
|---|---|
| `topic_arn` | ARN of the SNS topic |
| `alarm_names` | Names of all alarms |

## Usage

```hcl
module "monitoring" {
  source = "../../modules/monitoring"

  name                    = "my-app-dev"
  alert_emails            = ["ops@example.com"]
  alb_arn_suffix          = module.alb.arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  cluster_name            = module.ecs_service.cluster_name
  service_name            = module.ecs_service.service_name
  desired_count           = 1
  db_instance_identifier  = module.database.identifier
}
```

Requires Terraform `>= 1.10` and the AWS provider `~> 6.73`.
