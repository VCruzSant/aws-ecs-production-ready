data "aws_caller_identity" "current" {}

data "aws_elb_service_account" "current" {}

resource "aws_security_group" "this" {
  name        = "${var.name}-alb"
  description = "Public HTTP to the load balancer"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  #checkov:skip=CKV_AWS_260:Public HTTP is the entry point of the app; there is no domain for HTTPS yet.
  security_group_id = aws_security_group.this.id
  description       = "HTTP from the internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# The load balancer only ever talks to the app tasks, for traffic and health checks.
resource "aws_vpc_security_group_egress_rule" "app" {
  security_group_id            = aws_security_group.this.id
  description                  = "App port on the tasks"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = var.app_security_group_id
}

#trivy:ignore:AWS-0053 Public by design: it is the only entry point of the app.
resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_150:Deletion protection is a variable, off so the demo can be destroyed.
  #checkov:skip=CKV2_AWS_28:WAF adds about $8 a month for a demo with no real traffic; listed as a next step.
  #checkov:skip=CKV2_AWS_20:No domain yet, so there is no HTTPS listener to redirect to.
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.this.id]

  drop_invalid_header_fields = true
  enable_deletion_protection = var.enable_deletion_protection

  dynamic "access_logs" {
    for_each = var.access_logs_enabled ? [1] : []

    content {
      bucket  = aws_s3_bucket.access_logs[0].id
      enabled = true
    }
  }

  tags = var.tags

  # The load balancer checks that it can write to the bucket when logging is turned on.
  depends_on = [aws_s3_bucket_policy.access_logs]
}

resource "aws_lb_target_group" "app" {
  #checkov:skip=CKV_AWS_378:TLS would end at the load balancer; traffic to the tasks stays inside the VPC.
  name        = var.name
  target_type = "ip"
  protocol    = "HTTP"
  port        = var.app_port
  vpc_id      = var.vpc_id

  deregistration_delay = var.deregistration_delay

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags
}

#trivy:ignore:AWS-0054 No domain yet, so there is no certificate for HTTPS.
resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:No domain yet, so there is no certificate for HTTPS.
  #checkov:skip=CKV_AWS_103:No domain yet, so there is no HTTPS listener to set a TLS policy on.
  load_balancer_arn = aws_lb.this.arn
  protocol          = "HTTP"
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = var.tags
}

#trivy:ignore:AWS-0089 This is the log bucket; logging it would need yet another bucket.
#trivy:ignore:AWS-0090 Logs are written once and expire in days; versions would only keep them longer.
resource "aws_s3_bucket" "access_logs" {
  #checkov:skip=CKV_AWS_18:This is the log bucket; logging it would need yet another bucket.
  #checkov:skip=CKV_AWS_21:Logs are written once and expire in days; versions would only keep them longer.
  #checkov:skip=CKV_AWS_144:Short-lived logs do not need a copy in another region.
  #checkov:skip=CKV_AWS_145:Load balancer access logs support only SSE-S3.
  #checkov:skip=CKV2_AWS_62:Nothing consumes events from the log bucket.
  count = var.access_logs_enabled ? 1 : 0

  bucket        = "${var.name}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  count = var.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  count = var.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

#trivy:ignore:AWS-0132 Load balancer access logs support only SSE-S3.
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count = var.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  count = var.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.access_logs_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "access_logs" {
  count = var.access_logs_enabled ? 1 : 0

  statement {
    sid       = "LoadBalancerWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.current.arn]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.access_logs[0].arn,
      "${aws_s3_bucket.access_logs[0].arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  count = var.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id
  policy = data.aws_iam_policy_document.access_logs[0].json

  depends_on = [aws_s3_bucket_public_access_block.access_logs]
}
