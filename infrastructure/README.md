# Infrastructure Deployment Guide

This guide details the process for deploying the Velox "Agile Monolith" infrastructure on AWS using Terraform.

## Architecture Overview

The infrastructure is split into two layers to ensure **Extendability** and **Safety**:

1.  **Layer 1: Shared Network (`envs/non-prod`)**
    *   **Scope:** VPC, NAT Gateway, Application Load Balancer (ALB), VPN.
    *   **Frequency:** Deployed once.
    *   **Purpose:** Provides the physical foundation for all non-production environments (Dev, Staging).
2.  **Layer 2: Application Environments (`envs/dev`, `envs/staging`)**
    *   **Scope:** ECS Cluster, Fargate Services, RDS Database, Redis.
    *   **Frequency:** Deployed on every infrastructure change.
    *   **Purpose:** Deploys the actual application logic and data stores.

---

## 1. Prerequisites

*   [AWS CLI](https://aws.amazon.com/cli/) installed and configured with Administrator credentials.
*   [Terraform](https://www.terraform.io/) (v1.0+) installed.

---

## 2. Bootstrap (One Time Only)

Before deploying any Terraform, we need to set up the remote state backend (S3) and locking table (DynamoDB).

Run the following commands in your terminal:

```bash
# 1. Create S3 Bucket for State
aws s3api create-bucket --bucket my-app-tf-state --region us-east-1

# 2. Enable Versioning (Crucial for recovery)
aws s3api put-bucket-versioning --bucket my-app-tf-state --versioning-configuration Status=Enabled

# 3. Create DynamoDB Table for Locking
aws dynamodb create-table \
    --table-name my-app-tf-lock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region us-east-1
```

> **Note:** Replace `my-app-tf-state` and `my-app-tf-lock` with unique names if these are taken. You will need to update the `backend "s3"` configuration in all `main.tf` files if you change these names.

---

## 3. Deploy Layer 1: Shared Network

This sets up the VPC, ALB, and VPN.

1.  Navigate to the directory:
    ```bash
    cd infrastructure/envs/non-prod
    ```

2.  Initialize Terraform:
    ```bash
    terraform init
    ```

3.  Review and Apply:
    ```bash
    terraform apply
    # Type 'yes' to confirm
    ```

### Post-Deployment: Connect to VPN

Once Layer 1 is deployed, a Tailscale Subnet Router is running.

1.  Go to the [AWS Systems Manager Parameter Store](https://us-east-1.console.aws.amazon.com/systems-manager/parameters).
2.  Create a SecureString parameter named `/common/vpn/auth_key` with your Tailscale Auth Key (Ephemeral, Reusable).
3.  Reboot the VPN instance (or wait for it to pick it up if you added it to UserData).
4.  Approve the route `10.10.0.0/16` in your Tailscale Admin Console.

---

## 4. Deploy Layer 2: Dev Environment

This deploys the Velox Application into the Shared Network.

1.  Navigate to the directory:
    ```bash
    cd infrastructure/envs/dev
    ```

2.  Initialize Terraform:
    ```bash
    terraform init
    ```

3.  Review and Apply:
    ```bash
    terraform apply
    # Type 'yes' to confirm
    ```

### Secrets Management

The ECS task needs a `DATABASE_URL`.

1.  Go to AWS SSM Parameter Store.
2.  Find `/velox/dev/DATABASE_URL`.
3.  Update the value with the actual connection string (you can get the RDS endpoint from the Terraform output or AWS Console).
    *   Format: `postgres://postgres:PASSWORD@RDS_ENDPOINT:5432/velox_dev`

---

## 5. How to Add Staging

To create a Staging environment that mirrors Dev but is isolated:

1.  Create `infrastructure/envs/staging`.
2.  Copy all `.tf` files from `infrastructure/envs/dev`.
3.  Edit `main.tf`:
    *   Change `cluster_name` to `velox-cluster-staging`.
    *   Change `host_header` to `["staging.app.com"]`.
    *   Update Backend Key to `staging/app/terraform.tfstate`.
4.  Run `terraform init` and `terraform apply`.

This reuses the **same** VPC and ALB from Layer 1, saving costs while maintaining logical isolation.
