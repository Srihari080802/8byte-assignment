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