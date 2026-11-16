data "aws_caller_identity" "current" {}

#trivy:ignore:AWS-0095 CloudWatch cannot publish to a topic encrypted with the aws/sns key, and a CMK is billed for no gain on alert text.
resource "aws_sns_topic" "alerts" {
  #checkov:skip=CKV_AWS_26:CloudWatch cannot publish to a topic encrypted with the aws/sns key, and a CMK is billed for no gain on alert text.
  name = "${var.name}-alerts"

  tags = var.tags
}

data "aws_iam_policy_document" "topic" {
  statement {
    sid       = "CloudWatchAlarmsOfThisAccount"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudwatch:*:${data.aws_caller_identity.current.account_id}:alarm:${var.name}-*"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.topic.json
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

locals {
  alb_dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
  service_dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.service_name
  }
  db_dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarms = {
    "alb-healthy-hosts" = {
      description         = "No healthy task behind the load balancer. Check the service events and the task logs."
      namespace           = "AWS/ApplicationELB"
      metric_name         = "HealthyHostCount"
      dimensions          = local.alb_dimensions
      statistic           = "Minimum"
      comparison_operator = "LessThanThreshold"
      threshold           = 1
      treat_missing_data  = "breaching"
    }
    "alb-target-5xx" = {
      description         = "The app is returning 5xx responses. Check the app logs for errors."
      namespace           = "AWS/ApplicationELB"
      metric_name         = "HTTPCode_Target_5XX_Count"
      dimensions          = local.alb_dimensions
      statistic           = "Sum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.target_5xx_threshold
      treat_missing_data  = "notBreaching"
    }
    "alb-elb-5xx" = {
      description         = "The load balancer itself is returning 5xx, usually no healthy target. Check the target health."
      namespace           = "AWS/ApplicationELB"
      metric_name         = "HTTPCode_ELB_5XX_Count"
      dimensions          = { LoadBalancer = var.alb_arn_suffix }
      statistic           = "Sum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.elb_5xx_threshold
      treat_missing_data  = "notBreaching"
    }
    "alb-response-time-p95" = {
      description         = "Slow responses at p95. Check the task CPU and the database."
      namespace           = "AWS/ApplicationELB"
      metric_name         = "TargetResponseTime"
      dimensions          = local.alb_dimensions
      extended_statistic  = "p95"
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.response_time_p95_seconds
      treat_missing_data  = "notBreaching"
    }
    "ecs-cpu" = {
      description         = "Service CPU is high. Scale out or raise the task CPU."
      namespace           = "AWS/ECS"
      metric_name         = "CPUUtilization"
      dimensions          = local.service_dimensions
      statistic           = "Average"
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.cpu_threshold_percent
      treat_missing_data  = "notBreaching"
    }
    "ecs-memory" = {
      description         = "Service memory is high. Look for a leak or raise the task memory."
      namespace           = "AWS/ECS"
      metric_name         = "MemoryUtilization"
      dimensions          = local.service_dimensions
      statistic           = "Average"
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.memory_threshold_percent
      treat_missing_data  = "notBreaching"
    }
    "ecs-running-tasks" = {
      description         = "Fewer tasks running than desired. Check the service events and the stopped tasks."
      namespace           = "ECS/ContainerInsights"
      metric_name         = "RunningTaskCount"
      dimensions          = local.service_dimensions
      statistic           = "Minimum"
      comparison_operator = "LessThanThreshold"
      threshold           = var.desired_count
      treat_missing_data  = "breaching"
    }
    "rds-cpu" = {
      description         = "Database CPU is high. Check slow queries or resize the instance."
      namespace           = "AWS/RDS"
      metric_name         = "CPUUtilization"
      dimensions          = local.db_dimensions
      statistic           = "Average"
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.cpu_threshold_percent
      treat_missing_data  = "missing"
    }
    "rds-free-storage" = {
      description         = "Database storage is almost full. Increase the allocated storage."
      namespace           = "AWS/RDS"
      metric_name         = "FreeStorageSpace"
      dimensions          = local.db_dimensions
      statistic           = "Minimum"
      comparison_operator = "LessThanThreshold"
      threshold           = var.db_free_storage_bytes
      treat_missing_data  = "missing"
    }
    "rds-freeable-memory" = {
      description         = "Database memory is low. Check connections or resize the instance."
      namespace           = "AWS/RDS"
      metric_name         = "FreeableMemory"
      dimensions          = local.db_dimensions
      statistic           = "Minimum"
      comparison_operator = "LessThanThreshold"
      threshold           = var.db_freeable_memory_bytes
      treat_missing_data  = "missing"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name        = "${var.name}-${each.key}"
  alarm_description = each.value.description

  namespace          = each.value.namespace
  metric_name        = each.value.metric_name
  dimensions         = each.value.dimensions
  statistic          = try(each.value.statistic, null)
  extended_statistic = try(each.value.extended_statistic, null)

  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  period              = var.period_seconds
  evaluation_periods  = var.evaluation_periods
  treat_missing_data  = each.value.treat_missing_data

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags

  depends_on = [aws_sns_topic_policy.alerts]
}
