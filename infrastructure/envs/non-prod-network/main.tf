provider "aws" {
  region = "us-east-1"
  default_tags { tags = { Env = "non-prod", Project = "velox" } }
}

terraform {
  backend "s3" {
    bucket = "my-app-tf-state"
    key    = "non-prod/network/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "my-app-tf-lock"
  }
}

# 1. VPC (10.10.0.0/16 - Non Prod)
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "velox-non-prod"
  cidr = "10.10.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.10.1.0/24", "10.10.2.0/24"]  # ALB, NAT, VPN
  private_subnets = ["10.10.10.0/24", "10.10.11.0/24"] # Fargate, RDS

  # COST SAVING: One NAT Gateway shared across all AZs
  enable_nat_gateway = true
  single_nat_gateway = true 
}

# 2. Shared Application Load Balancer
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name    = "velox-alb-non-prod"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  # Security Group: Allow HTTP/HTTPS from anywhere
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
      # Default: Return 404 if no host header matches
      fixed_response = {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  }
}

# 3. Tailscale Subnet Router (VPN)
resource "aws_instance" "vpn" {
  ami           = "ami-0c7217cdde317cfec" # Ubuntu 22.04 (US East 1)
  instance_type = "t3.nano"
  subnet_id     = module.vpc.public_subnets[0]
  
  vpc_security_group_ids = [module.alb.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  user_data = <<-EOF
              #!/bin/bash
              echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
              sysctl -p /etc/sysctl.d/99-tailscale.conf
              curl -fsSL https://tailscale.com/install.sh | sh
              AUTH_KEY=$(aws ssm get-parameter --name "/common/vpn/auth_key" --with-decryption --query "Parameter.Value" --output text --region us-east-1)
              tailscale up --authkey=$AUTH_KEY --advertise-routes=10.10.0.0/16 --hostname=aws-non-prod
              EOF
  
  tags = { Name = "tailscale-router" }
}

# 4. Shared RDS (Postgres)
module "db" {
  source = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "velox-db-shared-non-prod"
  
  engine               = "postgres"
  engine_version       = "15"
  family               = "postgres15"
  major_engine_version = "15"
  instance_class       = "db.t4g.micro"

  allocated_storage     = 20
  storage_type          = "gp3"
  
  db_name  = "velox_shared" # Default DB, apps will use velox_dev/velox_staging
  username = "postgres"
  password = "temporary_password_change_me_in_console"
  port     = 5432

  vpc_security_group_ids = [aws_security_group.db.id]
  create_db_subnet_group = true
  subnet_ids             = module.vpc.private_subnets

  multi_az            = false
  deletion_protection = false
  skip_final_snapshot = true
}

# 5. Shared Redis
resource "aws_elasticache_subnet_group" "redis" {
  name       = "redis-subnet-non-prod"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "velox-redis-shared-non-prod"
  description          = "Shared Redis for Non-Prod"
  node_type            = "cache.t4g.micro"
  port                 = 6379
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]

  num_node_groups         = 1
  replicas_per_node_group = 0
}

# 6. Security Groups for Data Layer
resource "aws_security_group" "db" {
  name        = "velox-db-sg-non-prod"
  description = "Allow inbound traffic from VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
}

resource "aws_security_group" "redis" {
  name        = "velox-redis-sg-non-prod"
  description = "Allow inbound traffic from VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
}

# 7. Outputs
output "vpc_id"          { value = module.vpc.vpc_id }
output "private_subnets" { value = module.vpc.private_subnets }
output "alb_listener_arn"{ value = module.alb.listeners["http"].arn }
output "alb_sg_id"       { value = module.alb.security_group_id }
output "db_endpoint"     { value = module.db.db_instance_endpoint }
output "redis_endpoint"  { value = aws_elasticache_replication_group.redis.primary_endpoint_address }
