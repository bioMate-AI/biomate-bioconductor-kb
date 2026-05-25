# envs/dev — minimal import of long-running dev resources.
#
# The dev EC2 + its security group + DNS record predate this rebuild and
# have accreted enough dependencies (billing Lambdas, RDS via separate SGs,
# Lago integration, etc.) that pulling everything under TF in one shot is
# risky. This file imports only the load-bearing primary resources so that:
#   1. `terraform plan` here is a no-op (state matches reality).
#   2. Future changes (idle alarm wiring, SG rule updates) flow through TF.
#   3. Sibling resources (RDS in P2.2, secrets in P2.3, billing Lambdas
#      deferred per §6.1) will be added under TF management when their
#      respective phases land — not all at once.
#
# Imported (P2.1):
#   - EC2 i-06696b0d91f4346e0 (dev app host)
#   - Route53 A dev-public.biomate.ai
#   - CloudWatch idle alarm (created here as new — none existed before)
#
# NOT imported (yet — by design):
#   - Security group sg-0b2188a4d48d989b8 (cross-system rules; touch later)
#   - RDS, ElastiCache, billing Lambdas, Lago — deferred per plan §6.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket         = "biomate-terraform-state"
    key            = "dev/terraform.tfstate"
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
      Env       = "dev"
    }
  }
}

# ---------- Dev EC2 (existing) ----------
# Long-running dev host; SG kept untouched (sg-0b2188a4d48d989b8) — referenced
# by data source rather than imported so cross-system rules aren't churned.

data "aws_security_group" "dev_existing" {
  id = "sg-0b2188a4d48d989b8"
}

resource "aws_instance" "dev_app" {
  ami                    = "ami-06af99ca40d168b3b"  # placeholder — ignored
  instance_type          = "t3.large"
  subnet_id              = "subnet-09e4dce46682a6c60"
  vpc_security_group_ids = [data.aws_security_group.dev_existing.id]
  iam_instance_profile   = "BioMateEc2DeployProfile"

  root_block_device {
    volume_size           = 50  # actual is likely larger; ignored on import
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "BioMate-Production"   # historical tag, kept as-is
  }

  lifecycle {
    ignore_changes = [
      user_data, user_data_base64,
      ami,
      instance_type,           # don't try to resize an in-use dev host from TF
      root_block_device,       # actual size differs from TF default
      vpc_security_group_ids,  # SG churn risks billing/Lambda paths
    ]
  }
}

# ---------- Route53 A record (existing) ----------

resource "aws_route53_record" "dev_alias" {
  zone_id = "Z03470822JJ4UEOYJ53ZE"          # dev-public.biomate.ai
  name    = "dev-public.biomate.ai"
  type    = "A"
  ttl     = 60
  records = [aws_instance.dev_app.public_ip]
}

# ---------- Idle alarm (new — was missing on dev, caused the $1,400 orphan
# incident L14) ----------

resource "aws_cloudwatch_metric_alarm" "dev_idle" {
  alarm_name          = "biomate-deploy-dev-idle"
  alarm_description   = "Notify when dev EC2 has CPU<5% for 60min (L14 — idle-instance prevention)"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 12
  threshold           = 5
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { InstanceId = aws_instance.dev_app.id }
  alarm_actions       = ["arn:aws:sns:us-west-2:399683337364:biomate-deploy-events"]
}

output "dev_instance_id" { value = aws_instance.dev_app.id }
output "dev_public_ip"   { value = aws_instance.dev_app.public_ip }
output "dev_url"         { value = "https://dev-public.biomate.ai" }
