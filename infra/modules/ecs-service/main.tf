data "aws_region" "current" {}

locals {
  # The execution role may read exactly the secrets the task definition references.
  secret_arns = distinct([for v in values(var.secrets) : regex("^arn:[^:]+:secretsmanager:[^:]+:[^:]+:secret:[^:]+", v)])
}

data "aws_caller_identity" "current" {}

#trivy:ignore:AWS-0034 Container Insights is a variable, off by default in the module because it is billed per metric.
resource "aws_ecs_cluster" "this" {
  #checkov:skip=CKV_AWS_65:Container Insights is a variable, off by default in the module because it is billed per metric.
  name = var.name

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }

  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.container_insights]
}

# Created here because AWS would create it on its own and leave it behind after destroy.
#trivy:ignore:AWS-0017 CloudWatch Logs encrypts every log group by default; a KMS key adds cost and no protection here.
resource "aws_cloudwatch_log_group" "container_insights" {
  #checkov:skip=CKV_AWS_158:CloudWatch Logs encrypts every log group by default; a KMS key adds cost and no protection here.
  #checkov:skip=CKV_AWS_338:Retention is a variable; 7 days is enough for a demo.
  count = var.container_insights ? 1 : 0

  name              = "/aws/ecs/containerinsights/${var.name}/performance"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

#trivy:ignore:AWS-0017 CloudWatch Logs encrypts every log group by default; a KMS key adds cost and no protection here.
resource "aws_cloudwatch_log_group" "this" {
  #checkov:skip=CKV_AWS_158:CloudWatch Logs encrypts every log group by default; a KMS key adds cost and no protection here.
  #checkov:skip=CKV_AWS_338:Retention is a variable; 7 days is enough for a demo.
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Used by the ECS agent to start the task, never by the app code.
resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = var.tags
}

data "aws_iam_policy_document" "execution" {
  # GetAuthorizationToken does not support resource-level permissions.
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  dynamic "statement" {
    for_each = length(var.secrets) > 0 ? [1] : []

    content {
      sid       = "ReadSecrets"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = local.secret_arns
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "start-task"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

data "aws_iam_policy_document" "task_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    # Only ECS tasks from this account can assume the role.
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# Identity of the app code; permissions are added only when the app needs an AWS API.
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json

  tags = var.tags
}

resource "aws_security_group" "tasks" {
  name        = "${var.name}-tasks"
  description = "App tasks, reachable only from the load balancer"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-tasks" })
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "App port from the load balancer"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = var.alb_security_group_id
}

#trivy:ignore:AWS-0104 Without VPC endpoints, ECR, CloudWatch Logs and Secrets Manager are reached through the NAT.
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.tasks.id
  description       = "HTTPS to AWS APIs"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "to_security_groups" {
  for_each = var.egress_security_groups

  security_group_id            = aws_security_group.tasks.id
  description                  = "${each.key} on port ${each.value.port}"
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.security_group_id
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name                   = var.container_name
    image                  = var.image
    essential              = true
    readonlyRootFilesystem = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = [for k, v in var.environment : { name = k, value = v }]

    # ECS reads these when the task starts, so only the ARNs are in the task definition.
    secrets = [for k, v in var.secrets : { name = k, valueFrom = v }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = var.container_name
      }
    }
  }])

  tags = var.tags

  # Checked on create and update only, so destroy works without an image.
  lifecycle {
    precondition {
      condition     = var.image != null
      error_message = "image is required to create or update the task definition (set image_tag in the environment)."
    }
  }
}

resource "aws_ecs_service" "this" {
  name             = var.name
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.this.arn
  desired_count    = var.desired_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds

  # A deployment whose tasks never get healthy is stopped and rolled back to the last good one.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"
  wait_for_steady_state   = var.wait_for_steady_state

  tags = var.tags

  # The execution role must keep its permissions until the service is gone.
  depends_on = [aws_iam_role_policy.execution]

  # The deploy pipeline owns the running revision; Terraform only sets the first one.
  lifecycle {
    ignore_changes = [task_definition]
  }
}
