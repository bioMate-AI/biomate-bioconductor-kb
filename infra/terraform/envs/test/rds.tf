# RDS Postgres for the test env. Resolves the SQLite first-boot
# RevisionNotFoundError that blocked end-to-end Galaxy boot in P1.3 — Galaxy
# stamps its initial alembic revision cleanly when running against a fresh
# Postgres database.
#
# Sizing: db.t3.micro (~$13/mo) + 20GB gp3 (~$2/mo). Single-AZ, no backups,
# encrypted at rest. Stage and prod will use larger instance classes and
# Multi-AZ in their own envs.
#
# Secrets: master password lives in AWS Secrets Manager (test/biomate/rds-galaxy).
# deploy.sh fetches it at deploy time and writes to /opt/biomate/.env so the
# Galaxy container reads database_connection at boot.

# ---------- Master password in Secrets Manager ----------

resource "random_password" "rds_galaxy" {
  length  = 32
  special = false  # avoid URL-encoding pain in postgresql://… connection strings
}

resource "aws_secretsmanager_secret" "rds_galaxy" {
  name        = "test/biomate/rds-galaxy"
  description = "RDS Postgres master password for biomate-test-galaxy"
  # 7-day recovery window so we can resurrect if accidentally deleted.
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "rds_galaxy" {
  secret_id = aws_secretsmanager_secret.rds_galaxy.id
  secret_string = jsonencode({
    username = "galaxy"
    password = random_password.rds_galaxy.result
    engine   = "postgres"
    host     = aws_db_instance.galaxy.address
    port     = aws_db_instance.galaxy.port
    dbname   = aws_db_instance.galaxy.db_name
    url      = "postgresql://galaxy:${random_password.rds_galaxy.result}@${aws_db_instance.galaxy.address}:${aws_db_instance.galaxy.port}/${aws_db_instance.galaxy.db_name}"
  })
}

# ---------- Security group ----------
# Only the test EC2 SG can reach Postgres. Tightest possible scope.

resource "aws_security_group" "rds_galaxy" {
  name        = "biomate-test-rds-galaxy-sg"
  description = "BioMate test RDS Postgres - test EC2 only"
  vpc_id      = "vpc-00059887828237f1f"

  ingress {
    description     = "Postgres from test EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.test_app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- DB subnet group (need 2+ subnets in different AZs even for single-AZ RDS) ----------

data "aws_subnets" "default_vpc" {
  filter {
    name   = "vpc-id"
    values = ["vpc-00059887828237f1f"]
  }
}

resource "aws_db_subnet_group" "default" {
  name        = "biomate-test-db-subnet-group"
  description = "BioMate test RDS subnet group (default VPC subnets across AZs)"
  subnet_ids  = data.aws_subnets.default_vpc.ids
}

# ---------- RDS Postgres ----------

resource "aws_db_instance" "galaxy" {
  identifier     = "biomate-test-galaxy"
  engine         = "postgres"
  engine_version = "17.6"

  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "galaxy"
  username = "galaxy"
  password = random_password.rds_galaxy.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds_galaxy.id]
  publicly_accessible    = false

  multi_az                            = false
  backup_retention_period             = 0   # test env: no automated backups
  delete_automated_backups            = true
  skip_final_snapshot                 = true
  deletion_protection                 = false
  apply_immediately                   = true
  iam_database_authentication_enabled = false

  # Logs are optional for test; enable error log only.
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = {
    Name = "biomate-test-galaxy"
  }
}

output "rds_endpoint"           { value = aws_db_instance.galaxy.address }
output "rds_secret_arn"         { value = aws_secretsmanager_secret.rds_galaxy.arn }
output "rds_secret_name"        { value = aws_secretsmanager_secret.rds_galaxy.name }
