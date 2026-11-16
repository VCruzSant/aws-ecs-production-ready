data "aws_iam_policy_document" "grafana_reader_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "grafana_reader" {
  name                 = "${var.project}-grafana-readonly"
  description          = "Read-only access to CloudWatch for a local Grafana"
  assume_role_policy   = data.aws_iam_policy_document.grafana_reader_assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "grafana_reader" {
  #checkov:skip=CKV_AWS_356:The read-only metric, alarm and query calls do not support resource-level permissions.
  # These calls do not support resource-level permissions and only read.
  statement {
    sid = "ReadMetricsAndAlarms"
    actions = [
      "cloudwatch:DescribeAlarms",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "logs:DescribeLogGroups",
      "ec2:DescribeRegions",
      "tag:GetResources",
    ]
    resources = ["*"]
  }

  statement {
    sid = "QueryAppLogs"
    actions = [
      "logs:DescribeLogStreams",
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
    ]
    resources = ["arn:aws:logs:*:${local.account_id}:log-group:/ecs/${var.project}-*:*"]
  }

  # GetQueryResults and StopQuery have no resource that can be scoped.
  statement {
    sid       = "ManageOwnQueries"
    actions   = ["logs:GetQueryResults", "logs:StopQuery"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "grafana_reader" {
  name   = "read-cloudwatch"
  role   = aws_iam_role.grafana_reader.id
  policy = data.aws_iam_policy_document.grafana_reader.json
}
