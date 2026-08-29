# Architecture

Detailed notes on the infrastructure design, the reasoning behind each layer, and
the request path end to end.

## Overview

The system runs a containerised FastAPI application on AWS ECS Fargate, behind an
Application Load Balancer, backed by a PostgreSQL RDS instance. Everything is
provisioned by Terraform with remote state in S3.

```
Internet
   │
   ▼
Application Load Balancer          (public subnets, 2 AZs)
   │
   ▼
ECS Fargate task                   (private app subnets, 2 AZs)
   │
   ▼
RDS PostgreSQL                     (private data subnets, 2 AZs)
```

Outbound traffic from the Fargate task — pulling images from ECR, writing logs to
CloudWatch, reading secrets — routes through a NAT gateway in a public subnet.

## Network layer

### VPC

A single VPC at `10.0.0.0/16` with both `enable_dns_hostnames` and
`enable_dns_support` set to true. The former is off by default and is required for
RDS endpoint resolution: RDS returns a DNS name rather than an IP address, and
without DNS hostnames enabled the ECS task cannot resolve it. The failure presents
as a name-resolution error that looks nothing like a networking misconfiguration.

### Subnet layout

Six subnets across three tiers and two availability zones:

| Tier | AZ-a | AZ-b | Purpose |
|---|---|---|---|
| Public | 10.0.0.0/24 | 10.0.1.0/24 | ALB nodes, NAT gateway |
| Private app | 10.0.10.0/24 | 10.0.11.0/24 | ECS Fargate tasks |
| Private data | 10.0.20.0/24 | 10.0.21.0/24 | RDS instance |

Each `/24` provides 251 usable addresses — AWS reserves five per subnet. The gaps
between 1 and 10, and between 11 and 20, leave room to add subnets within a tier
later without renumbering the whole plan.

Availability zones are selected from the `aws_availability_zones` data source
rather than hardcoded. AWS randomises the mapping between AZ names and physical
zones per account, so `ap-south-1a` in one account is not necessarily the same
facility as in another. Using the data source also makes the configuration
region-portable: changing `var.aws_region` moves the whole stack.

Two AZs is the minimum rather than a choice. An ALB requires subnets in at least
two, and an RDS subnet group requires the same.

### Why three tiers rather than two

App and data subnets share a route table, so the separation is not about routing —
both need outbound access via NAT and neither accepts inbound traffic from the
internet. The separation is an isolation boundary. If the application tier were
compromised, the database still sits in a distinct network segment governed by its
own security group. Separation between the tiers is enforced by security groups,
not by routing.

### Routing

A subnet is public or private purely because of its route table. There is no flag
on the subnet resource that makes it one or the other.

**Public route table** — `0.0.0.0/0` to the internet gateway. Associated with both
public subnets.

**Private route table** — `0.0.0.0/0` to the NAT gateway. Associated with all four
private subnets.

The VPC-local route is created automatically by AWS and does not appear in the
Terraform configuration.

Public subnets also set `map_public_ip_on_launch = true`. This is a separate
mechanism from the route table: the route provides a path to the internet, while
the flag gives resources launched there a public address to be reached at. Both are
needed for a subnet to function as public.

### NAT gateway

The NAT sits in the first public subnet with an Elastic IP attached. It must be in
a public subnet because it needs its own route to the internet gateway — placing it
in a private subnet would create a routing loop where it routes to itself.

It exists because Fargate tasks in private subnets have no inbound route from the
internet, which is the point, but still need outbound access to pull images from
ECR, ship logs to CloudWatch, and read from Secrets Manager. NAT permits outbound
connections and their responses while blocking anything initiated from outside.
That asymmetry is the entire value.

A single NAT gateway serves both AZs. This is a cost decision at roughly $32/month
each, documented as a known availability tradeoff: an AZ failure would sever
outbound connectivity for workloads in the surviving zone. Production would run one
per AZ. VPC endpoints for ECR, S3 and CloudWatch Logs are the cheaper alternative
at low volume and would remove the NAT dependency entirely for these services.

### Explicit dependency on the internet gateway

The NAT gateway declares `depends_on = [aws_internet_gateway.gw]`. Terraform infers
dependencies from attribute references, and the NAT never references the IGW — but
AWS requires the gateway to be attached before NAT creation succeeds. This is one
of only two places in the configuration where the implicit dependency graph is
insufficient.

## Security groups

Three groups, chained by reference rather than by address:

| Group | Inbound | Source |
|---|---|---|
| ALB | 80, 443 | `0.0.0.0/0` |
| ECS tasks | 8000 | ALB security group ID |
| RDS | 5432 | ECS task security group ID |

Only the ALB rule contains a CIDR block. Everything below references the group
above it by ID, so the rules describe identity rather than addresses. Scaling from
one task to fifty, or replacing the load balancer, requires no security group
changes — the new resources inherit the same group membership and the rules
continue to apply.

The RDS group has no egress rule, since the database never initiates outbound
connections.

Rules are defined as separate `aws_vpc_security_group_ingress_rule` and
`aws_vpc_security_group_egress_rule` resources rather than inline blocks. The AWS
provider documentation now recommends this: inline rules struggle with multiple
CIDR blocks and lack unique IDs, tags and descriptions.

### Two-layer model

Route tables answer *where traffic can go*. Security groups answer *what is allowed
through*. They operate independently and both must permit a connection.

The RDS instance is protected twice: no route from the internet reaches its subnet,
**and** its security group accepts 5432 only from the ECS task group. A routing
misconfiguration alone would not expose it.

## Compute layer

### ECS Fargate

Fargate was chosen over EKS and EC2 launch type. EC2 would mean managing AMIs,
patching, SSH access and auto-scaling groups — operational surface that
demonstrates nothing the assignment asks for. EKS would suit the Kubernetes
experience but carries a large setup cost in node groups, IRSA and the AWS Load
Balancer Controller.

Fargate runs containers without any node management. For a team with a single
infrastructure owner, minimising operational surface is the right default.

`network_mode = "awsvpc"` is mandatory for Fargate. Each task receives its own
elastic network interface with a private IP, which is why the ALB target group must
use `target_type = "ip"` rather than the default `"instance"` — there is no EC2
instance to register.

### Task definition

CPU and memory are declared at task level rather than per container, because
Fargate allocates at task level. The combination 256 CPU units / 512 MB is the
smallest valid pairing; Fargate accepts only specific combinations and rejects
others at apply time.

The container definition specifies:

- **Image** from ECR, tagged `latest`
- **Port mapping** on 8000
- **Log configuration** using the `awslogs` driver, writing to `/ecs/8byte`
- **Secrets** injecting `DATABASE_URL` from Secrets Manager

### IAM roles

Two roles with the same trust policy — both assumed by
`ecs-tasks.amazonaws.com` — but very different permissions.

**Execution role.** Used by the ECS agent before the container starts: pulling the
image from ECR, creating the CloudWatch log stream, and fetching the database
secret. It carries the AWS-managed `AmazonECSTaskExecutionRolePolicy` plus an
inline policy granting `secretsmanager:GetSecretValue` on one specific secret ARN.

**Task role.** Used by the application process at runtime, via the container
credential endpoint. No permissions are attached, because the application makes no
AWS API calls.

The separation is the security boundary. The agent needs to read the database
password; the application receives that password as an environment variable and has
no reason to reach Secrets Manager. Under a single combined role, a compromised
application would inherit the ability to enumerate and read secrets. With the split,
it inherits nothing.

Neither role holds long-lived credentials. Roles are assumed via STS, which issues
short-lived tokens — there are no access keys anywhere in the running system.

## Load balancing

### Application Load Balancer

Internet-facing, spanning both public subnets. Layer 7 rather than a Network Load
Balancer, because it understands HTTP, can route by path or host header, and
performs HTTP health checks. ALBs also support security groups, which NLBs do not.

### Target group

The abstraction between the listener and the running containers. The ALB has no
knowledge of ECS; it knows a pool of IP:port targets. ECS registers and deregisters
task IPs as they start and stop.

Health check configuration:

| Setting | Value | Reasoning |
|---|---|---|
| Path | `/health` | Returns 200 without touching the database |
| Interval | 30s | |
| Timeout | 5s | Must be lower than the interval |
| Healthy threshold | 2 | Quick to trust recovery |
| Unhealthy threshold | 3 | Slower to condemn, so a single blip doesn't kill a task |

The health endpoint deliberately does not query PostgreSQL. If it did, a transient
database failure would cause every task to fail health checks simultaneously, the
ALB would deregister all of them, and a database blip would become a total outage.
A separate readiness check is the correct place for dependency verification.

### Listener

Port 80, HTTP, forwarding to the target group. Production would run two listeners:
443 with an ACM certificate, and 80 with a redirect action to HTTPS. That requires
a registered domain and is out of scope here.

### Health check grace period

The ECS service sets `health_check_grace_period_seconds = 120`. The application
waits for the database, creates its schema, then starts uvicorn — 20 to 30 seconds
in total. With the default of zero, the ALB began health checking immediately,
tasks failed, and ECS replaced them in a loop before any could finish starting.

## Data layer

RDS PostgreSQL on `db.t4g.micro` — Graviton-based, cheaper than the equivalent t3
class. Storage is `gp3` rather than the `gp2` default, at the 20 GB minimum.

Key settings:

- `publicly_accessible = false`
- `storage_encrypted = true`
- `multi_az = false` — a documented cost decision
- `backup_retention_period = 7` — daily automated backups with point-in-time
  recovery
- `skip_final_snapshot = true` — appropriate for an environment destroyed and
  rebuilt frequently; production would take a final snapshot

The DB subnet group spans both private data subnets.

### Credential handling

Terraform generates the password with `random_password`, restricted to a URL-safe
character set. The credential is consumed as a connection string, and characters
such as `@`, `?` and `#` carry meaning in a URI and would break parsing.

The full connection string is assembled and stored in Secrets Manager, referencing
the RDS endpoint. Terraform's dependency graph orders this correctly: the secret
version references `aws_db_instance.default.address`, so it cannot be created until
the database exists.

The ECS service declares an explicit dependency on the secret version. This is the
second place where the implicit graph is insufficient — the service references the
secret's ARN but not the version, so without `depends_on` Terraform can create the
service while the secret still has no value, and tasks fail with
`ResourceNotFoundException` for staging label `AWSCURRENT`.

## State management

Terraform state lives in S3 with:

- **Versioning enabled** — a corrupted or overwritten state file can be recovered
- **Server-side encryption** — the RDS password is stored in state in plaintext
- **Public access blocked** — for the same reason
- **Native locking** via `use_lockfile = true`, using S3 conditional writes.
  Terraform 1.10 introduced this, replacing the DynamoDB table that older guidance
  requires

Backend blocks cannot use variables, so these values are literal. That is a known
Terraform limitation rather than an oversight.

## Deployment flow

1. A pull request triggers tests against a PostgreSQL service container and a
   dependency scan
2. On merge to `main`, GitHub Actions assumes an AWS role via OIDC federation
3. The image is built, scanned with Trivy, and pushed to ECR with two tags: the
   commit SHA and `latest`
4. The staging job forces a new ECS deployment
5. The production job waits for manual approval via a GitHub environment protection
   rule, then deploys

No AWS credentials are stored in GitHub. The OIDC trust policy is conditioned on
the repository's immutable subject claim, which includes numeric user and repository
IDs, so the role cannot be assumed by a repository that later claims the same name.

## Request path

A complete request, end to end:

1. DNS resolves the ALB's public hostname to a node in one of the public subnets
2. The ALB listener accepts the connection on port 80
3. The ALB selects a healthy target from the target group — a task IP in a private
   app subnet
4. The ECS task security group permits inbound 8000 from the ALB security group
5. uvicorn serves the request
6. If the handler queries the database, it connects to the RDS endpoint on 5432;
   the RDS security group permits this from the ECS task security group
7. The response returns along the same path

Separately, at task start: the ECS agent pulls the image from ECR and reads the
secret from Secrets Manager, both routed outbound through the NAT gateway, and
container output streams to CloudWatch Logs.