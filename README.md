# 8Byte DevOps Assignment

Infrastructure, deployment automation and monitoring for a containerised FastAPI
application on AWS, provisioned entirely with Terraform.

## What this deploys

A three-tier VPC across two availability zones, an Application Load Balancer, an
ECS Fargate service running a Python API, and a PostgreSQL RDS instance in an
isolated subnet tier. Images are built and deployed through GitHub Actions using
OIDC federation, with no long-lived AWS credentials stored anywhere.

## Requirements coverage

| Requirement | Implementation |
|---|---|
| VPC with public and private subnets | `terraform/vpc.tf` — three tiers across two AZs |
| Application hosting | ECS Fargate — `terraform/ecs.tf` |
| RDS PostgreSQL | `terraform/rds.tf` |
| Security groups | `terraform/security.tf` — chained by group ID |
| Load balancer | `terraform/alb.tf` |
| `variables.tf` | All environment-specific values parameterised |
| State management | S3 backend with native locking — `terraform/backend.tf` |
| Outputs | `terraform/outputs.tf` |
| Tests on PR | `.github/workflows/pr-tests.yml` |
| Build and push on merge | `.github/workflows/deploy.yml` |
| Staging deployment | `deploy-staging` job |
| Manual production approval | `production` environment with required reviewer |
| Dependency scanning | `pip-audit` in the PR workflow |
| Container scanning | Trivy in the deploy workflow, plus ECR scan-on-push |
| Failure notification | Email via SMTP on workflow failure |
| Infrastructure metrics | Container Insights, RDS metrics |
| Application metrics | ALB request rate, error rate, latency |
| Database metrics | RDS CPU, connections, storage, memory |
| Application logs | CloudWatch log group `/ecs/8byte` |
| Access logs | ALB access logs to S3 |
| Dashboards | `8byte-application`, `8byte-infrastructure` |
| Secret management | Secrets Manager with scoped IAM policy |
| Backup strategy | RDS automated backups, 7-day retention |

## Architecture

Request path: internet → ALB (public subnets) → ECS Fargate task (private app
subnets) → RDS PostgreSQL (private data subnets).

| Tier | CIDRs | Contents |
|---|---|---|
| Public | 10.0.0.0/24, 10.0.1.0/24 | ALB, NAT gateway |
| Private app | 10.0.10.0/24, 10.0.11.0/24 | ECS Fargate tasks |
| Private data | 10.0.20.0/24, 10.0.21.0/24 | RDS PostgreSQL |

Security groups reference each other by ID rather than by CIDR: the ECS group
accepts traffic only from the ALB group, and RDS accepts 5432 only from the ECS
group. No rule below the ALB contains an IP range, so scaling the service or
replacing the load balancer requires no security group changes.

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with credentials
- Docker

## Setup

Create the state backend (one time — S3 bucket names are globally unique, so
substitute your own if this one is taken):

```bash
aws s3api create-bucket --bucket 8byte-tfstate-srihari-2026 --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

aws s3api put-bucket-versioning --bucket 8byte-tfstate-srihari-2026 \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket 8byte-tfstate-srihari-2026 \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block --bucket 8byte-tfstate-srihari-2026 \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

Update the bucket name in `terraform/backend.tf` if you used a different one, then
provision:

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Build and push the first image:

```bash
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin \
  570417736607.dkr.ecr.ap-south-1.amazonaws.com

cd app
docker build -t 570417736607.dkr.ecr.ap-south-1.amazonaws.com/8byte-app:latest .
docker push 570417736607.dkr.ecr.ap-south-1.amazonaws.com/8byte-app:latest
```

Set `container_image` in `terraform/variables.tf` to that URL and apply again, then
verify:

```bash
curl http://$(terraform output -raw alb_dns_name)/health
```

Tear down:

```bash
terraform destroy
```

## Running tests

Tests run against a real PostgreSQL instance, since importing the application
triggers a database connection at module level. The simplest local approach uses
the built image:

```bash
docker network create appnet

docker run -d --name pg --network appnet \
  -e POSTGRES_USER=appuser -e POSTGRES_PASSWORD=pass -e POSTGRES_DB=appdb \
  postgres:16-alpine

docker run --rm --network appnet \
  -e DATABASE_URL="postgresql://appuser:pass@pg:5432/appdb" \
  -e PYTHONPATH=/server \
  -v $(pwd):/server -w /server 8byte-app pytest tests/ -v
```

This matches how CI executes them and avoids local Python version differences.

## CI/CD

**`pr-tests.yml`** runs on pull requests against `main`. It starts a PostgreSQL
service container, installs dependencies, runs unit and integration tests, and
scans dependencies with `pip-audit`. Failures trigger an email notification.

**`deploy.yml`** runs on merge to `main`:

1. **build** — assumes the AWS role via OIDC, builds the image, scans it with
   Trivy, and pushes to ECR tagged with both the commit SHA and `latest`
2. **deploy-staging** — forces a new ECS deployment
3. **deploy-production** — gated behind the `production` GitHub environment, which
   requires manual approval before it runs

GitHub Actions authenticates through OIDC federation rather than stored access
keys. The role's trust policy is conditioned on this repository's immutable subject
claim, which embeds numeric user and repository IDs, so a renamed repository or
username cannot be impersonated by a third party claiming the old name.

Images are tagged with the commit SHA as well as `latest`, so any deployed image
can be traced to the commit that produced it and rolled back to by tag.

## Monitoring

Two CloudWatch dashboards:

**`8byte-application`** — request count, 5xx error count, target response time and
healthy host count, all sourced from ALB metrics. Measuring at the load balancer
captures what users actually experience rather than what the application reports
about itself.

**`8byte-infrastructure`** — ECS task CPU and memory via Container Insights, and
RDS CPU utilisation, database connections, free storage space and freeable memory.

The application also exposes Prometheus-format metrics at `/metrics` via
`prometheus-fastapi-instrumentator`. These are not currently scraped; a Grafana
Cloud or Amazon Managed Prometheus setup would consume them and is listed as future
work.

### Logging

Application stdout and stderr stream to the CloudWatch log group `/ecs/8byte` via
the `awslogs` driver, with 7-day retention.

ALB access logs are delivered to the S3 bucket `8byte-alb-logs-570417736607` every
five minutes, with public access blocked and server-side encryption enabled.

On system logs: Fargate provides no host operating system to collect logs from —
AWS manages the underlying compute. The container's stdout and stderr are the
closest equivalent in this model and are captured in CloudWatch. An EC2 launch type
would allow a CloudWatch agent on the host for OS-level logs.

## Secret management

The database password is generated by Terraform's `random_password`, stored in
Secrets Manager as a complete connection string, and injected into the container as
the `DATABASE_URL` environment variable by the ECS agent at task start.

The execution role's Secrets Manager policy is scoped to that single secret ARN
rather than `*`. The application process itself runs under a separate task role
with no permissions attached, so a compromised application cannot enumerate or read
secrets — it only sees the one value already injected into its environment.

The generated password is restricted to a URL-safe character set, since the
credential is consumed as a connection string and characters such as `@`, `?` and
`#` would break URI parsing.

## Backup strategy

RDS automated backups run daily with a seven-day retention window, enabling
point-in-time recovery to any moment within that period.

`skip_final_snapshot` is set to `true` because this environment is destroyed and
rebuilt frequently during development. Production would take a final snapshot on
deletion.

Terraform state is versioned in S3, so a corrupted or accidentally overwritten
state file can be restored from a previous version.

## Architecture decisions

**ECS Fargate over EKS or EC2.** Fargate removes node management entirely. EKS
would have consumed a large share of the time budget on node groups, IRSA and the
load balancer controller without demonstrating anything the assignment asks for.
For a team with a single infrastructure owner, reducing operational surface is the
right default.

**Three subnet tiers rather than two.** The app and data subnets share a route
table, so the separation is not about routing — it is an isolation boundary. If the
application tier is compromised, the database still sits in a distinct network
segment behind its own security group.

**Two availability zones.** An ALB requires at least two subnets in different AZs,
an RDS subnet group requires the same, and a single-AZ deployment has no failover
story.

**Single NAT gateway.** A deliberate cost decision at roughly $32/month each.
Production would run one per AZ so that an AZ failure does not sever outbound
connectivity for workloads in the other. VPC endpoints for ECR, S3 and CloudWatch
Logs are the cheaper alternative at low volume and are listed as future work.

**Separate task execution and task roles.** The execution role pulls images, writes
logs and reads the database secret — all before the container starts. The task role
is what the application process runs as, and has no permissions attached. Under a
single combined role, a compromised application would inherit Secrets Manager
access.

**S3-native state locking.** Terraform 1.10 introduced locking via S3 conditional
writes, so `use_lockfile = true` replaces the DynamoDB lock table that older
guidance requires. One less resource to provision and pay for.

**Health check separated from readiness.** `/health` returns 200 without touching
the database. If the health endpoint queried PostgreSQL and the database had a
transient failure, every task would fail health checks simultaneously and the ALB
would remove all of them — turning a database blip into a total outage.

**Health check grace period of 120 seconds.** The application waits for the
database, creates its schema, then starts the server, which takes 20–30 seconds.
With the default grace period of zero, the ALB began health checking immediately
and ECS replaced tasks before they could finish starting.

## Security considerations

- **No long-lived AWS credentials in CI.** GitHub Actions authenticates through
  OIDC federation. The trust policy is conditioned on this repository's immutable
  subject claim, so no other repository can assume the deployment role.
- **RDS is not publicly accessible**, is encrypted at rest, and sits in a subnet
  tier with no route to or from the internet.
- **Least-privilege IAM.** The Secrets Manager policy names a single secret ARN.
  `iam:PassRole` in the deployment role is scoped to the two ECS roles rather than
  `*`. ECR push permissions are scoped to the one repository, except
  `ecr:GetAuthorizationToken`, which AWS defines as account-level and cannot be
  scoped.
- **Non-root container.** The image creates an unprivileged user and switches to it
  before copying application code, with ownership set accordingly.
- **Multi-stage build.** Build tooling and wheels do not reach the final image.
- **Terraform state** is encrypted with SSE-S3, versioned for recovery, and has
  public access blocked. The database password is present in state in plaintext,
  which is precisely why these controls matter.
- **ALB access log bucket** has public access blocked and encryption enabled, and
  its bucket policy is conditioned on `aws:SourceAccount` so only this account's
  load balancers can write to it.
- **Infrastructure provisioned via a dedicated IAM user.** Root credentials were
  used only for initial account setup and are protected with MFA.

## Cost optimisation

- Fargate task sized at 0.25 vCPU / 0.5 GB, the smallest valid combination
- `db.t4g.micro` — Graviton-based, cheaper than the equivalent t3 instance class
- `gp3` storage rather than the `gp2` default
- CloudWatch log retention set to 7 days; the default is indefinite
- ECR lifecycle policy expiring untagged images after 14 days
- Single NAT gateway rather than one per AZ
- `default_tags` on the AWS provider applies `Project`, `Environment` and
  `ManagedBy` to every taggable resource, enabling cost attribution in Cost Explorer
- A budget alert is configured on the account
- The environment is destroyed between working sessions; a full rebuild takes
  roughly twelve minutes

Container Insights is enabled for ECS task-level metrics. It bills per custom
metric, which is negligible at one task but would need evaluating at higher task
counts — noted as a conscious tradeoff rather than an oversight.

## Known limitations and future work

- **Staging and production share one ECS service.** The pipeline has distinct jobs
  and a manual approval gate between them, but both deploy to the same target.
  Genuinely separate environments would parameterise the stack on `var.environment`
  with separate state keys.
- **HTTP only.** Production requires an ACM certificate, a 443 listener and an
  80→443 redirect. That needs a registered domain, which is out of scope here.
- **Schema is created at application startup** via `Base.metadata.create_all()`.
  Alembic migrations run as a pre-deployment step are the correct pattern.
- **Unit tests require a database.** Importing `app.main` opens a connection at
  module level, so even tests that touch no data need PostgreSQL running.
  Dependency injection for the session and lazy engine initialisation would fix
  this.
- **Dependency pins carry known CVEs.** `pip-audit` reports nine findings in
  Starlette without blocking the build. The pin exists because the sample
  application uses the older `TemplateResponse` signature; migrating six template
  calls would allow the pin to be removed. This is the first thing I would fix
  given more time.
- **Prometheus metrics are exposed but not scraped.** A Grafana Cloud agent sidecar
  or Amazon Managed Prometheus would consume `/metrics` and give application-level
  rather than load-balancer-level observability.
- **No alerting.** Dashboards exist but no CloudWatch alarms are configured. SNS
  topics with alarms on 5xx rate and unhealthy host count are the obvious next step.
- **Email notifications use a Gmail app password**, which bypasses 2FA. SES or a
  transactional email provider with a scoped API key is the production choice.
- **Self-review is permitted** on the production environment, as this is a solo
  project. A team would enable "Prevent self-review" and disable the administrator
  bypass.

## Repository layout

```
app/                  FastAPI application, Dockerfile, tests
terraform/            Infrastructure as code
.github/workflows/    CI/CD pipelines
docs/                 Architecture notes and challenges log
```

## Documentation

- [`docs/CHALLENGES.md`](docs/CHALLENGES.md) — problems encountered and how each
  was resolved
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — detailed architecture notes