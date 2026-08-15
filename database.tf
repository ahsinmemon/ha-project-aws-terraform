resource "aws_db_subnet_group" "main" {
  name       = "ha-project-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "ha-project-db-subet-group"
  }
}

resource "random_password" "db_password" {
  length           = 16
  special          = false
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "ha-project-db-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

resource "aws_db_instance" "main" {
  identifier           = "ha-project-db"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"

  allocated_storage    = 20
  storage_type         = "gp3"


  db_name             = "haproject"
  username            = "admin"
  password            = random_password.db_password.result

  multi_az = true
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 1
  skip_final_snapshot = true

  tags = {
    Name = "ha-project-db"
  }
}
