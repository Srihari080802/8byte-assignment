resource "aws_ecs_cluster" "app" {
  name = "${var.project_name}-ecs-cluster"

  tags = {
    Name = "${var.project_name}-ecs-cluster"
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name = "/ecs/${var.project_name}"

  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-ecs"
  }
}


resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      essential = true
      image     = var.container_image
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}