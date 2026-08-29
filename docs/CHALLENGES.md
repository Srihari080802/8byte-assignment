# Challenges and Resolutions

A record of the problems encountered while building this assignment and how
each was resolved.

## Cascading errors from a single unterminated string

**Issue:** `terraform fmt` reported six errors in `ecs.tf`, five of them
about "invalid multi-line string" on lines that looked correct.

**Cause:** A single missing closing quote in the `logConfiguration` block.
Everything after it was parsed as part of an unterminated string.

**Resolution:** Fixed only the first reported error and re-ran. Lesson:
with parse errors, fix the topmost one and re-run rather than trying to
interpret the rest.

## terraform validate passes but apply would fail

**Issue:** Used `gateway_id` for a route pointing at a NAT gateway.

**Cause:** `validate` checks schema, not semantics. `gateway_id` is a valid
argument on a route block — just the wrong one for a NAT gateway.

**Resolution:** Changed to `nat_gateway_id`. This showed a real limitation
of `validate` as a safety net.

## Malformed IAM policy ARN

**Issue:** Policy attachment would have failed with "policy not found".

**Cause:** Two errors — `arn:aws:iam:aws:` with a single colon instead of
`iam::aws:`, and `TaskExecute` instead of `TaskExecution`.

**Resolution:** Corrected to
`arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy`.
ARNs are strings, so no tooling catches this before apply.

## Referencing resources created with count

**Issue:** `aws_subnet.public.id` failed with an error about the resource
having `count` set.

**Cause:** Resources created with `count` are lists, not single objects.

**Resolution:** Used `[count.index]` for per-instance references and `[*]`
for full lists, e.g. `aws_subnet.private_data[*].id` for the DB subnet group.

## Data source used instead of resource

**Issue:** Wrote `data "aws_lb_target_group"` when a target group needed
creating.

**Cause:** The Terraform registry lists data sources and resources under the
same name in the sidebar. The data source looks up existing infrastructure;
the resource creates it.

**Resolution:** Switched to `resource "aws_lb_target_group"`.

## Documentation examples not portable to Fargate

**Issue:** The ECS task definition example in the provider docs used
`hostPort`, host volumes, and placement constraints — none valid on Fargate.

**Cause:** The leading example targets the EC2 launch type.

**Resolution:** Rewrote for Fargate: `network_mode = "awsvpc"`,
`requires_compatibilities = ["FARGATE"]`, CPU and memory at task level
rather than per container.

## RDS identifier naming constraint

**Issue:** `identifier = "8byte-postgres"` rejected — first character must
be a letter.

**Cause:** `var.project_name` is "8byte". AWS naming rules differ per
service: ALB names allow a leading digit, RDS identifiers do not, and DB
names disallow hyphens entirely.

**Resolution:** Prefixed the identifier as `db-8byte-postgres`.

## Deprecated DynamoDB state locking

**Issue:** `terraform init` warned that `dynamodb_table` is deprecated.

**Cause:** Terraform 1.10+ supports S3-native state locking via conditional
writes, removing the need for a separate lock table.

**Resolution:** Switched to `use_lockfile = true`.

## VS Code save conflict after terraform fmt

**Issue:** "The content of the file is newer" when saving `rds.tf`.

**Cause:** Ran `terraform fmt` while the file had unsaved editor changes.
`fmt` rewrote the file from its older on-disk state.

**Resolution:** Compared both versions and kept the editor's. Now save
before running `fmt`.

## HCL syntax habits from other languages

**Issue:** Semicolon at the end of an argument line.

**Cause:** Habit from C-style languages.

**Resolution:** HCL separates arguments with newlines, not semicolons.

## ECS service created before the secret had a value

**Issue:** Three tasks failed to start with `ResourceInitializationError: unable to
retrieve secret from asm ... ResourceNotFoundException: Secrets Manager can't find
the specified secret value for staging label: AWSCURRENT`.

**Cause:** Terraform created the ECS service at 06:37, but
`aws_secretsmanager_secret_version` only completed at 06:44 after RDS finished
provisioning. The secret container existed; its value did not. There is no attribute
reference between the service and the secret version, so Terraform's implicit
dependency graph did not order them.

**Resolution:** Added `aws_secretsmanager_secret_version.db` to the service's
`depends_on`. Note that `depends_on` changes never appear in a plan diff, since they
affect Terraform's ordering rather than AWS state.

## Health check grace period killed tasks during startup

**Issue:** Tasks were repeatedly marked unhealthy and replaced, visible in service
events as "(port 8000) is unhealthy ... due to (reason Health checks failed)".

**Cause:** `healthCheckGracePeriodSeconds` defaults to 0. The application runs
`wait_for_db`, creates tables, then starts uvicorn — roughly 20-30 seconds. The ALB
began health checking immediately, failed, and ECS replaced the task before it could
finish starting.

**Resolution:** Set `health_check_grace_period_seconds = 120` on the ECS service.

## Local Python version incompatible with pinned dependencies

**Issue:** `pip install -r requirements.txt` failed building `pydantic-core` with
"the configured Python interpreter version (3.14) is newer than PyO3's maximum
supported version (3.13)".

**Cause:** Ubuntu 26.04 ships Python 3.14. `pydantic-core==2.23.4` has no prebuilt
wheel for 3.14, so pip attempted a source build through Rust, and PyO3 0.22 does not
support that version. The container was unaffected because it pins `python:3.11-slim`.

**Resolution:** Ran the test suite inside the container with a volume mount rather
than a local virtualenv, which also matches how CI executes tests.

## Removing a dependency pin broke every template route

**Issue:** The integration test failed with `TypeError: unhashable type: 'dict'`
inside Jinja2's template cache.

**Cause:** `starlette==1.3.1` was removed from requirements because it appeared
inconsistent with the FastAPI version. Unpinned resolution then installed Starlette
1.6.0, which changed the `TemplateResponse` signature. The old form,
`TemplateResponse(name, {"request": request})`, causes Jinja2 to build a cache key
containing a dict.

**Resolution:** Pinned `prometheus-fastapi-instrumentator==7.0.0` and
`starlette<0.47`. The correct long-term fix is migrating the six template calls to
`TemplateResponse(request, name, context)`; recorded as future work.

## ECR repository blocked terraform destroy

**Issue:** `RepositoryNotEmptyException: The repository with name '8byte-app' cannot
be deleted because it still contains images`.

**Cause:** ECR refuses deletion of a non-empty repository by default.

**Resolution:** Set `force_delete = true` on the repository. Appropriate for an
ephemeral environment; production would leave this false so an accidental destroy
cannot remove image history.

## RDS identifier naming constraint

**Issue:** `first character of "identifier" must be a letter`.

**Cause:** `var.project_name` is "8byte", so the identifier became `8byte-postgres`.
AWS naming rules vary per service: ALB names permit a leading digit, RDS identifiers
do not, and DB names disallow hyphens entirely.

**Resolution:** Prefixed the identifier as `db-8byte-postgres`.

## Docker CLI unavailable in WSL despite integration being enabled

**Issue:** `The command 'docker' could not be found in this WSL 2 distro`, although
WSL integration was already toggled on in Docker Desktop.

**Cause:** Docker Desktop was not running. The integration setting persists whether
or not the engine is up, and the CLI shim is only available while it runs.

**Resolution:** Started Docker Desktop.

## OIDC role assumption failed with no diagnostic detail

**Issue:** The deploy workflow failed at the credentials step with
`Could not assume role with OIDC: Not authorized to perform
sts:AssumeRoleWithWebIdentity`, after twelve retry attempts.

**Cause:** The trust policy expected a subject claim of
`repo:Srihari080802/8byte-assignment:*`, following the format shown in AWS and
GitHub documentation. GitHub now issues **immutable subject claims** for
repositories created or renamed after 15 July 2026, embedding numeric user and
repository IDs:
`repo:Srihari080802@106571747/8byte-assignment@1349274357`. The setting is enabled
automatically and cannot be disabled. The two strings never matched, so the
condition failed.

**Resolution:** Copied the exact prefix from Settings → Actions → OIDC and used it
as the `github_repo` variable value. The error message names neither the claim
received nor the condition that failed, so diagnosis required eliminating each
possibility in turn: verifying the trust policy document, the OIDC provider's
client ID list, the canonical username casing via `gh api user`, and the repository
workflow permissions, before finding the subject claim configuration page.

## Dependency scan failed the build despite continue-on-error

**Issue:** `pip-audit` reported nine known vulnerabilities in Starlette 0.46.2 and
exited non-zero, failing the job even though the step was marked
`continue-on-error: true`.

**Cause:** The step property alone did not suppress the job-level failure in this
configuration.

**Resolution:** Appended `|| true` to the command so the shell returns zero
regardless. The findings still print in full, so the vulnerabilities are visible
rather than suppressed. The underlying CVEs stem from the Starlette pin required by
the sample application's older `TemplateResponse` signature — recorded as immediate
future work, since migrating six template calls would allow the pin to be removed.

## ECS service cycled through both deployments after a task definition update

**Issue:** After updating `container_image` and applying, CloudWatch logs continued
showing nginx entrypoint output rather than the application, and the service
reported `failedTasks: 3` against the previous revision.

**Cause:** ECS rolls deployments gradually. The previous revision's tasks were still
being health-checked and replaced while the new revision was starting, so three
deployments appeared simultaneously in `describe-services`.

**Resolution:** Forced the rollout with `aws ecs update-service
--force-new-deployment` and confirmed the primary deployment's task definition ARN
ended in `:2`. Stale deployments drained once one healthy task stabilised.

## Uncommitted changes appeared on the wrong branch

**Issue:** Terraform changes made while on `main` were visible after switching to a
new branch.

**Cause:** Uncommitted working directory changes are not associated with a branch;
git carries them across checkouts.

**Resolution:** Switched back to `main` and committed there. Understanding this
avoids the instinct to stash or re-create work unnecessarily.