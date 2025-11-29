provider "aws" {
  region = "us-east-1"
  default_tags { tags = { Env = "prod", Project = "velox" } }
}

terraform {
  backend "s3" {
    bucket = "my-app-tf-state"
    key    = "prod/network/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "my-app-tf-lock"
  }
}

# 1. VPC (10.20.0.0/16 - Prod)
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "velox-prod"
  cidr = "10.20.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.20.1.0/24", "10.20.2.0/24"]
  private_subnets = ["10.20.10.0/24", "10.20.11.0/24"]

  # Prod: Dedicated NAT Gateway per AZ (High Availability)
  enable_nat_gateway = true
  single_nat_gateway = false 
  one_nat_gateway_per_az = true
}

# 2. Dedicated ALB
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name    = "velox-alb-prod"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
    all_https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      fixed_response = {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  }
}

# 3. Outputs
output "vpc_id"          { value = module.vpc.vpc_id }
output "private_subnets" { value = module.vpc.private_subnets }
output "alb_listener_arn"{ value = module.alb.listeners["http"].arn }
output "alb_sg_id"       { value = module.alb.security_group_id }
