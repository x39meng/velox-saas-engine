This document serves as the **Master Architectural Reference** for Project Velox. It provides a comprehensive, deep-dive explanation of the system's design, decision-making framework, and operational procedures.

-----

# Project Velox: Technical Design Specification (v5.0)

## 1\. Architectural Philosophy & Goals

### 1.1 The Primary Directive

The Velox architecture is optimized for a specific constraint: **A high-velocity agile team (\<10 engineers) operating with strict reliability requirements.**

Unlike enterprise architectures that prioritize isolation at the cost of complexity (e.g., microservices mesh), Velox prioritizes **Integration Efficiency** and **Refactor Safety**.

### 1.2 Core Principles

1.  **Schema-First Design:** The database schema is the single source of truth. It dictates the TypeScript types used in the API, the frontend, and the validation logic. We rely on the compiler to catch regression bugs.
2.  **Headless Business Logic:** Business rules are strictly decoupled from delivery mechanisms (HTTP/Next.js). Logic exists as pure functions, enabling 100% code reuse across different entry points.
3.  **The Agile Monolith:** We deploy logical microservices (Web, API, Worker) as a physical monolith (Shared Infrastructure). This reduces "Ops Tax" (managing multiple load balancers) while maintaining code modularity.
4.  **Infrastructure as Code (IaC) Parity:** Application constants (Ports, Service Names) are defined in TypeScript and synchronized to Terraform automatically. There are no "magic numbers" in the infrastructure configurations.

-----

## 2\. Technology Stack Deep Dive

### 2.1 Runtime & Build

  * **Bun (Development):** Chosen for its sub-second startup times and rapid package installation (`bun install` is \~25x faster than npm). Used for local development, scripting, and CI/CD logic.
  * **Node.js (Production):** Chosen for ecosystem maturity. We use the standard Node.js runtime inside Docker containers (via Next.js Standalone mode) to ensure maximum compatibility with AWS SDKs and APM tools like Sentry.
  * **Turborepo:** Manages the monorepo workspace. Configured to use Remote Caching to prevent re-building or re-testing code that hasn't changed.

### 2.2 Application Layer

  * **Next.js (App Router):** Serves the internal User Interface. We utilize **Server Actions** exclusively for mutations, which allows the UI to import backend logic directly. This eliminates the network round-trip overhead of an internal API fetch.
  * **Hono:** Serves the Public API. Chosen over Express for its strict adherence to Web Standards (Request/Response objects) and lightweight footprint.
  * **BullMQ + Redis:** Handles asynchronous workloads. Used for reliable job processing (e.g., CSV imports, PDF generation) and **Repeatable Jobs** (Cron replacements).
  * **Drizzle ORM:** Chosen over Prisma for its "zero-runtime" architecture and SQL-like syntax. It allows for atomic schema updates that propagate type errors instantly across the entire stack.

-----

## 3\. System Architecture: The "Headless" Pattern

The defining characteristic of Velox is the separation of **Logic** from **Transport**.

### 3.1 Directory Structure

The repository is organized to enforce dependency rules:

  * **`packages/core` (The Nucleus):** Contains Zod schemas, Drizzle interactions, and pure business functions. It *never* imports from `apps/*`.
  * **`apps/web` (The Head):** Imports `@repo/core`. Handles React rendering and Server Action binding.
  * **`apps/api` (The Head):** Imports `@repo/core`. Handles HTTP Request parsing, Headers, and Status Codes.

### 3.2 Data Flow Example: User Creation

In a traditional system, the Web App calls the API. In Velox, both call the Core.

1.  **Scenario A: Internal User Signup (Web)**

      * **Trigger:** User submits `<form action={signupAction}>`.
      * **Execution:** `signupAction` imports `createUser` from `@repo/core`.
      * **Result:** The function runs inside the Next.js server runtime. **Latency: 0ms network overhead.**

2.  **Scenario B: Mobile App Signup (API)**

      * **Trigger:** Mobile app `POST /v1/users`.
      * **Execution:** Hono handler validates JSON body, then calls `createUser` from `@repo/core`.
      * **Result:** Identical logic execution. If `createUser` changes, both Web and API break at build time, forcing a safe refactor.

-----

## 4\. Infrastructure & Network Topology

We utilize **AWS ECS Fargate** managed via **Terraform**. The network design enforces security via physics (network isolation) rather than just policy.

👉 **[Read the Full Infrastructure Deployment Guide](./infrastructure/README.md)**

### 4.1 The 2-VPC Isolation Model

To prevent accidental destruction of production data via Terraform state collision or human error, we implement strict physical separation.

  * **VPC A (Non-Prod):** Hosts the **Dev** and **Staging** environments.
      * **Optimization:** Shares a single NAT Gateway across both environments to save \~$32/month.
      * **Purpose:** Destructive testing, integration verification.
  * **VPC B (Production):** Hosts the **Production** environment.
      * **Isolation:** Dedicated NAT Gateway. Completely separate Terraform state file. It is mathematically impossible for a Terraform command running in `envs/dev` to reference a resource in VPC B.

### 4.2 Subnet Tiering

Resources are placed in subnets based on their connectivity needs:

  * **Public Subnets:** Host the **Application Load Balancer (ALB)** and **NAT Gateway**. Direct route to Internet Gateway.
  * **Private Subnets:** Host **Fargate Containers** and **RDS Databases**. No direct ingress from the internet. Outbound traffic routes via NAT.

### 4.3 The "Agile Monolith" Deployment

We use a single ALB to route traffic to different containers based on **Host Headers**.

  * `admin.app.com` $\rightarrow$ Routes to Admin Container.
  * `api.app.com` $\rightarrow$ Routes to API Container.
  * `app.app.com` $\rightarrow$ Routes to Web Container.

**Why?** This avoids the cost and complexity of managing 3 separate Load Balancers while maintaining logical separation of concerns.

-----

## 5\. Security Architecture

Security is applied in layers, using the most efficient tool for the specific threat vector.

### 5.1 Static Edge Security (AWS WAF)

  * **Admin Console Protection:** An IP Set containing Office and VPN IPs is attached to the WAF. Rules block any request to `admin.app.com` that does not originate from this allowed list. This blocks attacks *before* they reach the application server.
  * **Public App Protection:** AWS Managed Rules (Common Rule Set, Bot Control) are applied to `app.app.com` to prevent scraping and generic exploits (SQLi, XSS).

### 5.2 Dynamic Application Security (Middleware)

  * **Client API Allowlist:** Since client IP lists are dynamic and large, they cannot be managed in WAF/Terraform.
  * **Implementation:** A Hono Middleware intercepts requests to `api.app.com`. It validates the API Key, fetches the associated Organization from the database, and compares the request's `x-forwarded-for` IP against the organization's `allowed_ips` JSON array.

### 5.3 VPN Access (Tailscale)

  * **Problem:** Developers need access to private RDS instances.
  * **Solution:** We deploy a **Tailscale Subnet Router** (t3.nano) in each VPC.
  * **Benefit:** Developers authenticate via SSO. The VPC network (`10.10.0.0/16`) becomes accessible from their laptop without managing SSH keys or opening Bastion ports to the public internet.

-----

## 6\. Secrets & Configuration Management

### 6.1 The "Secret Waterfall"

We do not bake secrets into Docker images. We utilize **AWS SSM Parameter Store** as the centralized source of truth.

1.  **Definition:** Secrets are defined in Terraform as placeholder resources (lifecycle `ignore_changes`).
2.  **Management:** Actual values are set securely via the AWS Console or scripts.
3.  **Runtime:** When Fargate starts a task, the ECS Agent reads the parameter from SSM and injects it as an environment variable (`process.env`).

### 6.2 Local Development Config

We use **Cascading Overrides** to allow developers to context-switch between local and remote resources safely.

  * `.env` (Default): Connects to local Docker Compose database.
  * `.env.dev` (Gitignored): Overrides `DATABASE_URL` to point to the Remote Dev RDS (via Tailscale).
  * **Workflow:** `bun run dev:dev` uses `dotenv-cli` to load the overrides, enabling a developer to debug a cloud issue from their laptop.

-----

## 7\. CI/CD & Automation

### 7.1 The "Bun Shell" Pipeline

We reject complex YAML logic in favor of TypeScript. The CI/CD pipeline is defined in a script (`scripts/pipeline.ts`) executed by **Bun Shell**.

  * **Benefit:** The exact same deployment logic can be run locally for debugging.
  * **Steps:**
    1.  **Quality:** Parallel execution of Lint, Typecheck, and Integration Tests.
    2.  **Build:** Docker build and push to ECR with Git SHA tagging.
    3.  **Sync:** A script reads `packages/config` and generates `terraform.tfvars.json`.
    4.  **Deploy:** `terraform apply` updates the ECS Service to the new image tag.

### 7.2 Deployment Strategy

  * **Rolling Updates:** ECS performs a zero-downtime rolling update, draining connections from old tasks before killing them.
  * **Asset Handling:** We use **Monolithic Containers** (Next.js Standalone). Static assets (`_next/static`) serve from the container, not S3. This eliminates "Version Skew" where a user on an old client requests a JS chunk that was deleted from S3 during a new deployment.

-----

## 8\. Observability Strategy

### 8.1 The "Power Duo" Stack

We balance cost and fidelity by using two specialized tools:

1.  **Axiom (Traces & Logs):** Configured for **100% Sampling**. All logs and OTel traces are ingested.
      * *Implementation:* **Pino** logger injects the OpenTelemetry `trace_id` into every log line. This allows us to view the logs for a specific request in the context of its full trace waterfall.
2.  **Sentry (Exceptions):** Configured for **Error Only** reporting.
      * *Implementation:* Global middleware injects `User ID` and `Tenant ID` scope.
      * *Sentry Crons:* Acts as a "Dead Man's Switch." If a BullMQ job fails to check in, Sentry alerts the team.

-----

## 9\. Testing Strategy

We follow the "Agile Testing Trophy," prioritizing high-value Integration tests over granular Unit tests.

1.  **Integration Tests (Vitest):**
      * **Target:** `packages/core`.
      * **Scope:** Tests business logic functions against a Dockerized Test Database.
      * **Goal:** Prove that `createUser` writes the correct SQL to Postgres.
2.  **End-to-End Tests (Playwright):**
      * **Target:** `apps/web`.
      * **Scope:** Tests critical user journeys (Login, Billing, Onboarding) against the **Dev** environment.
      * **Goal:** Prove that the full stack (UI -\> Server Action -\> Core -\> DB) works together.
3.  **Unit Tests:**
      * **Target:** Utilities.
      * **Scope:** Only used for complex algorithmic logic (e.g., regex validation, math).

-----

## 10\. Developer Workflow

### 10.1 Getting Started

```bash
# 1. Install dependencies (Bun is 25x faster than npm)
bun install

# 2. Start Local Infrastructure (Postgres, Redis)
docker-compose up -d

# 3. Push Drizzle Schema
bun run db:push

# 4. Start Development Server (Web + API + Worker in parallel)
bun run dev
```

### 10.2 Connecting to Remote Infrastructure

To debug an issue in the **Dev** environment:

```bash
# 1. Ensure Tailscale is connected
# 2. Run with Dev overrides
bun run dev:dev

# Or for Staging
bun run dev:staging
```

This starts the local Next.js server but connects it to the AWS Dev RDS instance and Redis cache.