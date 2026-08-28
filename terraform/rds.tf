resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = aws_subnet.private_data[*].id

  tags = {
    Name = "${var.project_name}-rds-subnet-group"
  }
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}


resource "aws_secretsmanager_secret" "rds_db_secret" {
  name                    = "${var.project_name}-rds-db-secret"
  recovery_window_in_days = 0
  tags = {
    Name = "${var.project_name}-rds-db-secret"
  }
}

resource "aws_db_instance" "default" {
  identifier              = "db-${var.project_name}-postgres"
  db_name                 = var.db_name
  engine                  = "postgres"
  allocated_storage       = var.db_allocated_storage
  storage_type            = "gp3"
  instance_class          = var.db_instance_class
  username                = var.db_username
  password                = random_password.password.result
  db_subnet_group_name    = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible     = false
  storage_encrypted       = true
  backup_retention_period = 7
  multi_az                = false
  skip_final_snapshot     = true
  apply_immediately       = true
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.rds_db_secret.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.password.result
    host     = aws_db_instance.default.address
    port     = 5432
    dbname   = var.db_name
  })
}