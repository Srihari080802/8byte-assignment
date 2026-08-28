resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "ALB Security Group HTTP/HTTPS allow"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-tasks"
  description = "ECS Security Group to allow the container ports"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-ecs-tasks"
  }
}


resource "aws_vpc_security_group_ingress_rule" "ecs_tasks_container_allow" {
  security_group_id            = aws_security_group.ecs_tasks.id
  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port                    = var.container_port
  ip_protocol                  = "tcp"
  to_port                      = var.container_port
}


resource "aws_vpc_security_group_egress_rule" "ecs_tasks_all" {
  security_group_id = aws_security_group.ecs_tasks.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_security_group" "rds" {
  name        = "rds"
  description = "RDS Security Group to allow the ports"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-rds"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_postgres" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.ecs_tasks.id
  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
}
