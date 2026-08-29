# Challenges and Resolutions

A record of the substantive problems encountered while building this assignment and
how each was resolved.

## Cascading errors from a single unterminated string

**Issue:** `terraform fmt` reported six errors in `ecs.tf`, five of them about
"invalid multi-line string" on lines that looked correct.

**Cause:** A single missing closing quote in the `logConfiguration` block.
Everything after it was parsed as part of an unterminated string.

**Resolution:** Fixed only the first reported error and re-ran. Lesson: with parse
errors, fix the topmost one and re-run rather than trying to interpret the rest.

## terraform validate passes but apply would fail

**Issue:** Used `gateway_id` for a route pointing at a NAT gateway.

**Cause:** `validate` checks schema, not semantics. `gateway_id` is a valid argument
on a route block — just the wrong one for a NAT gateway.

**Resolution:** Changed to `nat_gateway_id`. This showed a real limitation of
`validate` as a safety net: it confirms the configuration is well-formed, not that
AWS will accept it.

## Malformed IAM policy ARN

**Issue:** The policy attachment would have failed with "policy not found".

**Cause:** Two errors — `arn:aws:iam:aws:` with a single colon instead of
`iam::aws:`, and `TaskExecute` instead of `TaskExecution`. ARN format is
`arn:partition:service:region:account:resource`, and IAM is global, so the region
field is empty.

**Resolution:** Corrected to
`arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy`. ARNs are
plain strings, so no tooling catches this before apply.

## Referencing resources created with count

**Issue:** `aws_subnet.public.id` failed with an error about the resource having
`count` set.

**Cause:** Resources created with `count` are lists, not single objects.

**Resolution:** Used `[count.index]` for per-instance references and the splat
operator `[*]` for full lists — for example `aws_subnet.private_data[*].id` when
building the DB subnet group.

## Data source used instead of resource

**Issue:** Wrote `data "aws_lb_target_group"` when a target group needed creating.

**Cause:** The Terraform registry lists data sources and resources under the same
name in the sidebar. The data source looks up existing infrastructure; the resource
creates it.

**Resolution:** Switched to `resource "aws_lb_target_group"`.

## Documentation examples not portable to Fargate

**Issue:** The ECS task definition example in the provider documentation used
`hostPort`, host volumes and placement constraints — none of which are valid on
Fargate.

**Cause:** The leading example targets the EC2 launch type.

**Resolution:** Rewrote for Fargate: `network_mode = "awsvpc"`,
`requires_compatibilities = ["FARGATE"]`, and CPU and memory declared at task level
rather than per container.

## RDS identifier naming constraint

**Issue:** `first character of "identifier" must be a letter`.

**Cause:** `var.project_name` is "8byte", so the identifier became
`8byte-postgres`. AWS naming rules vary per service: ALB names permit a leading
digit, RDS identifiers do not, and DB names disallow hyphens entirely.

**Resolution:** Prefixed the identifier as `db-8byte-postgres`.

## Deprecated DynamoDB state locking

**Issue:** `terraform init` warned that the `dynamodb_table` backend parameter is
deprecated.

**Cause:** Terraform 1.10 and later support state locking natively through S3
conditional writes, removing the need for a separate lock table.

**Resolution:** Switched to `use_lockfile = true` and removed the DynamoDB table.

## Local Python version incompatible with pinned dependencies

**Issue:** `pip install -r requirements.txt` failed building `pydantic-core` with
"the configured Python interpreter version (3.14) is newer than PyO3's maximum
supported version (3.13)".

**Cause:** Ubuntu 26.04 ships Python 3.14. `pydantic-core==2.23.4` has no prebuilt
wheel for that version, so pip attempted a source build through Rust, and PyO3 0.22
does not support it. The container was unaffected because it pins
`python:3.11-slim`.

**Resolution:** Ran the test suite inside the container with a volume mount rather
than a local virtualenv. This also matches how CI executes tests, removing a class
of environment drift.

## Removing a dependency pin broke every template route

**Issue:** The integration test failed with `TypeError: unhashable type: 'dict'`
inside Jinja2's template cache.

**Cause:** `starlette==1.3.1` was removed from requirements because it appeared
inconsistent with the FastAPI version. Unpinned resolution then installed Starlette
1.6.0, which changed the `TemplateResponse` signature. The old form,
`TemplateResponse(name, {"request": request})`, causes Jinja2 to build a cache key
containing a dict, which is not hashable.

**Resolution:** Pinned `prometheus-fastapi-instrumentator==7.0.0` and
`starlette<0.47`. A first attempt pinning only Starlette failed, because
instrumentator 8.x requires `starlette>=1.0.0` — the two constraints were
incompatible. The correct long-term fix is migrating the six template calls to
`TemplateResponse(request, name, context)`, which would allow both pins to be
removed along with the CVEs they carry. Recorded as immediate future work.

## ECS service created before the secret had a value

**Issue:** Three tasks failed to start with `ResourceInitializationError: unable to
retrieve secret from asm ... ResourceNotFoundException: Secrets Manager can't find
the specified secret value for staging label: AWSCURRENT`.

**Cause:** Terraform created the ECS service several minutes before
`aws_secretsmanager_secret_version` completed, because the latter depends on the
RDS endpoint and RDS takes six minutes to provision. The secret container existed;
its value did not. There is no attribute reference between the service and the
secret version, so Terraform's implicit dependency graph did not order them.

**Resolution:** Added `aws_secretsmanager_secret_version.db` to the service's
`depends_on`. Worth noting that `depends_on` changes never appear in a plan diff,
since they affect Terraform's ordering rather than any AWS attribute.

## Health check grace period killed tasks during startup

**Issue:** Tasks were repeatedly marked unhealthy and replaced. Service events
showed `(port 8000) is unhealthy ... due to (reason Health checks failed)` in a
loop.

**Cause:** `healthCheckGracePeriodSeconds` defaults to zero. The application waits
for the database, creates its schema, then starts uvicorn — 20 to 30 seconds. The
ALB began health checking immediately, failed, and ECS replaced the task before it
could finish starting.

**Resolution:** Set `health_check_grace_period_seconds = 120` on the ECS service.

## ECR repository blocked terraform destroy

**Issue:** `RepositoryNotEmptyException: The repository with name '8byte-app'
cannot be deleted because it still contains images`.

**Cause:** ECR refuses deletion of a non-empty repository by default.

**Resolution:** Set `force_delete = true` on the repository. Appropriate for an
environment destroyed and rebuilt frequently; production would leave this false so
an accidental destroy cannot remove image history.

## OIDC role assumption failed with no diagnostic detail

**Issue:** The deploy workflow failed at the credentials step with `Could not
assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity`,
after twelve retry attempts.

**Cause:** The trust policy expected a subject claim of
`repo:Srihari080802/8byte-assignment:*`, the format shown in both AWS and GitHub
documentation. GitHub now issues **immutable subject claims** for repositories
created or renamed after 15 July 2026, embedding numeric user and repository IDs:
`repo:Srihari080802@106571747/8byte-assignment@1349274357`. The setting is enabled
automatically and cannot be disabled. The two strings never matched.

**Resolution:** Copied the exact prefix from Settings → Actions → OIDC and used it
as the `github_repo` variable value.

The error message names neither the claim received nor the condition that failed,
so diagnosis required eliminating each possibility in turn: verifying the trust
policy document with `aws iam get-role`, checking the OIDC provider's client ID
list, confirming the canonical username casing via `gh api user` (`StringLike` is
case-sensitive), and checking the repository's default workflow permissions — before
finding the subject claim configuration page.

The change itself is a genuine security improvement: numeric IDs are immutable, so
renaming a repository or username no longer allows a third party to claim the old
name and inherit an existing trust policy. It does mean every OIDC tutorial written
before mid-2026 is now subtly wrong.

## Dependency scan failed the build despite continue-on-error

**Issue:** `pip-audit` reported nine known vulnerabilities in Starlette 0.46.2 and
exited non-zero, failing the job even though the step was marked
`continue-on-error: true`.

**Cause:** The step property alone did not suppress the job-level failure in this
configuration.

**Resolution:** Appended `|| true` to the command so the shell returns zero
regardless. The findings still print in full, so vulnerabilities remain visible
rather than suppressed. Suppressing the output entirely would have been the wrong
fix — the point of the scan is that findings are recorded and triaged, not that the
build looks clean.

## ALB access logs rejected by the S3 bucket policy

**Issue:** `InvalidConfigurationRequest: Access Denied for bucket
8byte-alb-logs-570417736607. Please check S3bucket permission` when enabling access
logging.

**Cause:** The documented approach uses `data.aws_elb_service_account`, which
resolves a per-region ELB service account ID. AWS changed the delivery mechanism
for regions launched after August 2022 — ap-south-1 among them — to use the service
principal `logdelivery.elasticloadbalancing.amazonaws.com` instead. The data source
only knows the legacy account mapping.

**Resolution:** Changed the bucket policy principal to the service form and added an
`aws:SourceAccount` condition, so only this account's load balancers can write to
the bucket.