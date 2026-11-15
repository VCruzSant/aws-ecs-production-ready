locals {
  name = "${var.project}-${var.environment}"
}

module "network" {
  source = "../../modules/network"

  name     = local.name
  vpc_cidr = var.vpc_cidr
  az_count = var.az_count

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  enable_flow_logs = var.enable_flow_logs
}

module "ecr" {
  source = "../../modules/ecr"

  name = local.name
}

module "alb" {
  source = "../../modules/alb"

  name                  = local.name
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  app_port              = var.app_port
  app_security_group_id = module.ecs_service.security_group_id

  access_logs_enabled = var.alb_access_logs
}

module "ecs_service" {
  source = "../../modules/ecs-service"

  name                  = local.name
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.target_group_arn
  ecr_repository_arn    = module.ecr.repository_arn

  environment = {
    DB_HOST        = module.database.address
    DB_PORT        = tostring(module.database.port)
    DB_NAME        = module.database.db_name
    DB_SSLMODE     = "verify-full"
    DB_SSLROOTCERT = "/etc/ssl/certs/rds-ca.pem"
  }

  secrets = {
    DB_USER     = "${module.database.master_user_secret_arn}:username::"
    DB_PASSWORD = "${module.database.master_user_secret_arn}:password::"
  }

  egress_security_groups = {
    postgres = {
      port              = module.database.port
      security_group_id = module.database.security_group_id
    }
  }

  image          = var.image_tag == null ? null : "${module.ecr.repository_url}:${var.image_tag}"
  container_port = var.app_port
  cpu            = var.task_cpu
  memory         = var.task_memory
  desired_count  = var.desired_count

  container_insights = var.container_insights
}

module "database" {
  source = "../../modules/database"

  name                  = local.name
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  app_security_group_id = module.ecs_service.security_group_id

  instance_class = var.db_instance_class
  multi_az       = var.db_multi_az
}
