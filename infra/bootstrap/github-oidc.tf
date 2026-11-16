locals {
  deploy_enabled = var.github_repository != null

  # Built from the naming convention of infra/envs, so the bootstrap never reads an environment state.
  deploy_name   = "${var.project}-${var.deploy_environment}"
  deploy_region = coalesce(var.deploy_region, var.region)
  account_id    = data.aws_caller_identity.current.account_id
  ecs_prefix    = "arn:aws:ecs:${local.deploy_region}:${local.account_id}"
  cluster_arn   = "${local.ecs_prefix}:cluster/${local.deploy_name}"
  family_arn    = "${local.ecs_prefix}:task-definition/${local.deploy_name}:*"
}

# One per account; import it if the account already has it.
resource "aws_iam_openid_connect_provider" "github" {
  count = local.deploy_enabled ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_deploy_assume" {
  count = local.deploy_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only jobs that run in this GitHub environment of this repository.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:${var.deploy_environment}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  count = local.deploy_enabled ? 1 : 0

  name                 = "${local.deploy_name}-github-deploy"
  description          = "Assumed by GitHub Actions to deploy the app image to ${local.deploy_name}"
  assume_role_policy   = data.aws_iam_policy_document.github_deploy_assume[0].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_deploy" {
  count = local.deploy_enabled ? 1 : 0

  # GetAuthorizationToken does not support resource-level permissions.
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = ["arn:aws:ecr:${local.deploy_region}:${local.account_id}:repository/${local.deploy_name}"]
  }

  # DescribeTaskDefinition does not support resource-level permissions and only reads.
  statement {
    sid       = "EcsReadTaskDefinition"
    actions   = ["ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid       = "EcsRegisterTaskDefinition"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = [local.family_arn]
  }

  # Copies the tags of the previous revision, and nothing else can be tagged.
  statement {
    sid       = "EcsTagOnRegister"
    actions   = ["ecs:TagResource"]
    resources = [local.family_arn]

    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values   = ["RegisterTaskDefinition"]
    }
  }

  statement {
    sid       = "EcsDescribeService"
    actions   = ["ecs:DescribeServices"]
    resources = ["${local.ecs_prefix}:service/${local.deploy_name}/${local.deploy_name}"]
  }

  statement {
    sid       = "EcsUpdateService"
    actions   = ["ecs:UpdateService"]
    resources = ["${local.ecs_prefix}:service/${local.deploy_name}/${local.deploy_name}"]

    condition {
      test     = "ArnLike"
      variable = "ecs:task-definition"
      values   = [local.family_arn]
    }
  }

  statement {
    sid       = "EcsRunMigration"
    actions   = ["ecs:RunTask"]
    resources = [local.family_arn]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [local.cluster_arn]
    }
  }

  statement {
    sid       = "EcsDescribeTasks"
    actions   = ["ecs:DescribeTasks"]
    resources = ["${local.ecs_prefix}:task/${local.deploy_name}/*"]
  }

  statement {
    sid     = "PassTaskRoles"
    actions = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${local.deploy_name}-execution",
      "arn:aws:iam::${local.account_id}:role/${local.deploy_name}-task",
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # Prints the migration log when it fails.
  statement {
    sid       = "ReadMigrationLogs"
    actions   = ["logs:GetLogEvents"]
    resources = ["arn:aws:logs:${local.deploy_region}:${local.account_id}:log-group:/ecs/${local.deploy_name}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  count = local.deploy_enabled ? 1 : 0

  name   = "deploy-app"
  role   = aws_iam_role.github_deploy[0].id
  policy = data.aws_iam_policy_document.github_deploy[0].json
}
