locals {
  engine_major = split(".", var.engine_version)[0]
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.private_subnet_ids

  tags = var.tags
}

resource "aws_security_group" "this" {
  name        = "${var.name}-db"
  description = "Postgres, reachable only from the app tasks"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-db" })
}

resource "aws_vpc_security_group_ingress_rule" "from_app" {
  security_group_id            = aws_security_group.this.id
  description                  = "Postgres from the app tasks"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = var.app_security_group_id
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-postgres${local.engine_major}-"
  family      = "postgres${local.engine_major}"
  description = "Postgres ${local.engine_major} with TLS required"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
    # Static on current engines; the group is attached at creation, so the first boot already enforces it.
    apply_method = "pending-reboot"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

#trivy:ignore:AWS-0077 Backups are a variable, off so the demo leaves no snapshot behind.
#trivy:ignore:AWS-0177 Deletion protection is a variable, off so the demo can be destroyed.
#trivy:ignore:AWS-0176 The app uses the password from Secrets Manager; IAM auth comes with a dedicated app user.
#trivy:ignore:AWS-0133 Not used by a demo that lives for minutes; turn it on for real workloads.
resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_133:Backups are a variable, off so the demo leaves no snapshot behind.
  #checkov:skip=CKV_AWS_293:Deletion protection is a variable, off so the demo can be destroyed.
  #checkov:skip=CKV_AWS_161:The app uses the password from Secrets Manager; IAM auth comes with a dedicated app user.
  #checkov:skip=CKV_AWS_353:Not used by a demo that lives for minutes; turn it on for real workloads.
  #checkov:skip=CKV_AWS_129:RDS creates the log group for exported logs, and destroy would leave it behind.
  #checkov:skip=CKV_AWS_118:Needs another IAM role and leaves an RDSOSMetrics log group behind after destroy.
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # An engine past standard support is upgraded instead of billed for Extended Support.
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.username
  port     = var.port

  # RDS generates the password and keeps it in Secrets Manager, so it never reaches the state.
  manage_master_user_password = true

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.this.name

  auto_minor_version_upgrade = true
  backup_retention_period    = var.backup_retention_period
  copy_tags_to_snapshot      = true
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : "${var.name}-final"
  deletion_protection        = var.deletion_protection
  apply_immediately          = var.apply_immediately

  tags = var.tags
}
