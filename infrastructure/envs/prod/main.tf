provider "aws" {
  region = "us-east-1"
  default_tags { tags = { Env = "prod", Project = "velox" } }
}

terraform {
  backend "s3" {
    bucket = "my-app-tf-state"
    key    = "prod/app/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "my-app-tf-lock"
  }
}

# 1. Read the Prod Network State
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "my-app-tf-state"
    key    = "prod/network/terraform.tfstate"
    region = "us-east-1"
  }
}

# 2. Dedicated RDS (Postgres)
module "db" {
  source = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "velox-db-prod"
  
  engine               = "postgres"
  engine_version       = "15"
  family               = "postgres15"
  major_engine_version = "15"
  instance_class       = "db.t4g.medium" # Larger for Prod

  allocated_storage     = 100
  storage_type          = "gp3"
  
  db_name  = "velox_prod"
  username = "postgres"
  password = "temporary_password_change_me_in_console"
  port     = 5432

  vpc_security_group_ids = [aws_security_group.db.id]
  create_db_subnet_group = true
  subnet_ids             = data.terraform_remote_state.network.outputs.private_subnets

  multi_az            = true # High Availability
  deletion_protection = true
  skip_final_snapshot = false
}

# 3. Dedicated Redis
resource "aws_elasticache_subnet_group" "redis" {
  name       = "redis-subnet-prod"
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnets
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "velox-redis-prod"
  description          = "BullMQ Prod"
  node_type            = "cache.t4g.small"
  port                 = 6379
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]

  num_node_groups         = 2 # High Availability
  replicas_per_node_group = 1
}

# 4. ECS Cluster
module "ecs" {
  source = "terraform-aws-modules/ecs/aws"
  version = "~> 5.0"
  cluster_name = "velox-cluster-prod"

  fargate_capacity_providers = {
    FARGATE = { default_capacity_provider_strategy = { weight = 100 } } # No Spot for Prod
  }
}

# 5. ECS Service
resource "aws_ecs_service" "web" {
  name            = "web-service-prod"
  cluster         = module.ecs.cluster_id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 2 # Minimum 2 for HA
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.terraform_remote_state.network.outputs.private_subnets
    security_groups = [aws_security_group.app.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 3000
  }
}

# 6. Load Balancer Rules
resource "aws_lb_target_group" "web" {
  name        = "tg-web-prod"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id
  target_type = "ip"
  health_check { path = "/api/health" }
}

resource "aws_lb_listener_rule" "prod_routing" {
  listener_arn = data.terraform_remote_state.network.outputs.alb_listener_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    host_header {
      values = ["app.com"]
    }
  }
}
