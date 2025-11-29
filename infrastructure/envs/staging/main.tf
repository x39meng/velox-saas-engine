provider "aws" {
  region = "us-east-1"
  default_tags { tags = { Env = "staging", Project = "velox" } }
}

terraform {
  backend "s3" {
    bucket = "my-app-tf-state"
    key    = "staging/app/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "my-app-tf-lock"
  }
}

# 1. Read the Shared Network State
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "my-app-tf-state"
    key    = "non-prod/network/terraform.tfstate"
    region = "us-east-1"
  }
}

# 2. ECS Cluster
module "ecs" {
  source = "terraform-aws-modules/ecs/aws"
  version = "~> 5.0"
  cluster_name = "velox-cluster-staging"

  fargate_capacity_providers = {
    FARGATE = { default_capacity_provider_strategy = { weight = 50 } }
    FARGATE_SPOT = { default_capacity_provider_strategy = { weight = 50 } }
  }
}

# 3. ECS Service
resource "aws_ecs_service" "web" {
  name            = "web-service-staging"
  cluster         = module.ecs.cluster_id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
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

# 4. Load Balancer Rules
resource "aws_lb_target_group" "web" {
  name        = "tg-web-staging"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id
  target_type = "ip"
  health_check { path = "/api/health" }
}

resource "aws_lb_listener_rule" "staging_routing" {
  listener_arn = data.terraform_remote_state.network.outputs.alb_listener_arn
  priority     = 101

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    host_header {
      values = ["stg.app.com"]
    }
  }
}
