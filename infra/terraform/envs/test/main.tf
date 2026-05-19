# envs/test — imports of resources created by hand during P1.3 session
# (2026-05-18). After `terraform import`, `terraform plan` should be a no-op.
#
# Resources represented here:
#   - EC2 i-0482a6fa98c6f301a       (the deploy.sh test host)
#   - Security group sg-0a70bb26e47332c55
#   - Route53 A record stage-public.biomate.ai
#   - SNS topic biomate-deploy-events
#   - CloudWatch idle alarm biomate-deploy-test-idle
#
# Out of state (intentionally — they're cross-env shared and managed elsewhere):
#   - IAM role BioMateEc2DeployRole / instance profile
#   - IAM role GitHubActionsECRPush + OIDC provider
#   - ECR repos biomate/dev-backend, biomate/dev-frontend (lifecycle policies)
#   - VPC default + ECR VPC endpoints

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket         = "biomate-terraform-state"
    key            = "test/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "biomate-terraform-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-west-2"
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Project   = "biomate-cicd-rebuild"
      Env       = "test"
    }
  }
}

# ---------- Existing test EC2 + its security group ----------
# Created 2026-05-18 via aws-cli during P1.3.
# Imported as part of P2.1 — TF does not recreate, it adopts.

resource "aws_security_group" "test_app" {
  name        = "biomate-test-deploy-sg"
  description = "BioMate deploy.sh test EC2 - SSH from operator IP, HTTP/app ports public"
  vpc_id      = "vpc-00059887828237f1f"

  ingress {
    description = "SSH operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["104.63.31.236/32"]
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
}

resource "aws_instance" "test_app" {
  ami                    = "ami-06af99ca40d168b3b"  # ubuntu 24.04 noble 2026-05-15
  instance_type          = "t3.medium"
  subnet_id              = "subnet-09e4dce46682a6c60"
  vpc_security_group_ids = [aws_security_group.test_app.id]
  iam_instance_profile   = "BioMateEc2DeployProfile"

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "biomate-deploy-test"
  }

  # user_data + ami may differ from what TF would compute; don't fight it.
  lifecycle {
    ignore_changes = [user_data, user_data_base64, ami]
  }
}

# ---------- Route53 A record on the existing stage-public.biomate.ai zone ----------
# Hosted zone is shared with the future stage env; the A record itself is
# test-scoped today (points at the test EC2).

resource "aws_route53_record" "test_alias" {
  zone_id = "Z0363771X6YPSJQMFRN8"          # stage-public.biomate.ai
  name    = "stage-public.biomate.ai"
  type    = "A"
  ttl     = 60
  records = [aws_instance.test_app.public_ip]
}

# ---------- SNS topic for deploy events ----------

resource "aws_sns_topic" "deploy_events" {
  name = "biomate-deploy-events"
}

# Email subscription is left out of TF on purpose: SNS email subscriptions
# require manual confirmation by the recipient; managing them in TF causes
# perma-drift between `pending` and `confirmed` states. Subscribe via console
# or `aws sns subscribe` and confirm via the email link.

# ---------- Idle alarm on test EC2 ----------

resource "aws_cloudwatch_metric_alarm" "test_idle" {
  alarm_name          = "biomate-deploy-test-idle"
  alarm_description   = "Notify when test EC2 has CPU<5% for 60min"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 12
  threshold           = 5
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { InstanceId = aws_instance.test_app.id }
  alarm_actions       = [aws_sns_topic.deploy_events.arn]
}

output "test_instance_id"   { value = aws_instance.test_app.id }
output "test_public_ip"     { value = aws_instance.test_app.public_ip }
output "test_url"           { value = "http://stage-public.biomate.ai" }
output "sns_topic_arn"      { value = aws_sns_topic.deploy_events.arn }
