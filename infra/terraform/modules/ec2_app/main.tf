# modules/ec2_app
#
# An EC2 host running the BioMate app stack (galaxy backend + frontend
# containers via docker-compose). Pairs each host with:
#   - dedicated security group (SSH from operator IP, app HTTP ports public)
#   - CloudWatch idle alarm (CPU<5% for 60min → SNS notify)
#
# This module is intentionally minimal — it's an early-stage IaC scaffold for
# P2.1. P2.4 (stage) and P4.1 (prod) will extend it (ALB + ACM, RDS link,
# blue/green wiring if we ever go multi-instance per §3.1.1 of the plan).

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "env"             { type = string }
variable "instance_type"   { type = string, default = "t3.medium" }
variable "ami_id"          { type = string }
variable "subnet_id"       { type = string }
variable "vpc_id"          { type = string }
variable "instance_profile_name" {
  type        = string
  description = "Pre-existing IAM instance profile (BioMateEc2DeployProfile)."
}
variable "operator_cidr" {
  type        = string
  description = "Operator IP CIDR for SSH ingress (e.g. 1.2.3.4/32)."
}
variable "sns_alarm_topic_arn" {
  type        = string
  description = "SNS topic for the idle alarm to notify."
}
variable "root_volume_gb" {
  type    = number
  default = 50              # L22: never less than 50GB on app hosts
}
variable "user_data" {
  type    = string
  default = ""
}

locals {
  name   = "biomate-${var.env}"
  common_tags = {
    Env       = var.env
    ManagedBy = "terraform"
    Project   = "biomate-cicd-rebuild"
  }
}

resource "aws_security_group" "app" {
  name        = "${local.name}-app-sg"
  description = "BioMate ${var.env} app host: SSH operator only, HTTP/app ports public"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.operator_cidr]
  }
  ingress {
    description = "HTTP frontend"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "frontend direct"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "galaxy backend"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${local.name}-app-sg" })
}

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = var.instance_profile_name
  user_data              = var.user_data

  root_block_device {
    volume_size           = var.root_volume_gb
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = merge(local.common_tags, {
    Name = "biomate-deploy-${var.env}"
  })
  volume_tags = merge(local.common_tags, {
    Name = "biomate-deploy-${var.env}-root"
  })

  lifecycle {
    # Imported resources may have user_data + ami values that differ from
    # what TF would set on a fresh launch. Ignore those to keep plans clean
    # post-import. Re-bake the AMI via a deliberate replacement when we
    # actually want a fresh image.
    ignore_changes = [user_data, ami]
  }
}

resource "aws_cloudwatch_metric_alarm" "idle" {
  alarm_name          = "biomate-deploy-${var.env}-idle"
  alarm_description   = "Notify when ${var.env} EC2 has CPU<5% for 60min (L14 — idle-instance prevention)"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 12
  threshold           = 5
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { InstanceId = aws_instance.app.id }
  alarm_actions       = [var.sns_alarm_topic_arn]
  tags                = local.common_tags
}

output "instance_id"        { value = aws_instance.app.id }
output "public_ip"          { value = aws_instance.app.public_ip }
output "security_group_id"  { value = aws_security_group.app.id }
