resource "aws_cloudwatch_dashboard" "app" {
  dashboard_name = "${var.project_name}-application"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            [
              "AWS/ApplicationELB",
              "RequestCount",
              "LoadBalancer",
              aws_lb.alb.arn_suffix
            ]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Request count"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            [
              "AWS/ApplicationELB",
              "HTTPCode_Target_5XX_Count",
              "LoadBalancer",
              aws_lb.alb.arn_suffix
            ]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "5xx errors"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            [
              "AWS/ApplicationELB",
              "TargetResponseTime",
              "LoadBalancer",
              aws_lb.alb.arn_suffix
            ]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Target response time"
        }
      },

      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            [
              "AWS/ApplicationELB",
              "HealthyHostCount",
              "TargetGroup",
              aws_lb_target_group.app.arn_suffix,
              "LoadBalancer",
              aws_lb.alb.arn_suffix
            ]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Healthy hosts"
        }
      },


    ]
  })
}
resource "aws_cloudwatch_dashboard" "infrastructure" {
  dashboard_name = "${var.project_name}-infrastructure"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            [
              "ECS/ContainerInsights",
              "CpuUtilized",
              "ServiceName",
              aws_ecs_service.app.name,
              "ClusterName",
              aws_ecs_cluster.app.name
            ],
            [
              "ECS/ContainerInsights",
              "MemoryUtilized",
              "ServiceName",
              aws_ecs_service.app.name,
              "ClusterName",
              aws_ecs_cluster.app.name
            ]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "ECS CPU and memory"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            [
              "AWS/RDS",
              "CPUUtilization",
              "DBInstanceIdentifier",
              aws_db_instance.default.identifier
            ]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "RDS CPU"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            [
              "AWS/RDS",
              "DatabaseConnections",
              "DBInstanceIdentifier",
              aws_db_instance.default.identifier
            ]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "RDS connections"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            [
              "AWS/RDS",
              "FreeStorageSpace",
              "DBInstanceIdentifier",
              aws_db_instance.default.identifier
            ],
            [
              "AWS/RDS",
              "FreeableMemory",
              "DBInstanceIdentifier",
              aws_db_instance.default.identifier
            ]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "RDS storage and memory"
        }
      }
    ]
  })
}
