# BioMate Billing System - Production Deployment Guide

**Last Updated**: 2026-02-09
**Status**: Ready for deployment (107/107 tests passing)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Infrastructure Setup](#infrastructure-setup)
3. [Lambda Deployment](#lambda-deployment)
4. [Lago Setup](#lago-setup)
5. [Backend Integration](#backend-integration)
6. [Testing & Validation](#testing--validation)
7. [Monitoring & Alerts](#monitoring--alerts)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required AWS Resources
- **VPC**: Existing VPC with private subnets for ElastiCache
- **EC2 Instance**: Running BioMate backend (or ECS/Fargate task)
- **AWS Batch**: Compute environments + job queues configured
- **S3 Buckets**: Workflow results bucket (e.g., `biomate-nextflow-work`)

### Required Tools
```bash
# AWS CLI v2
aws --version  # ≥ 2.0.0

# Python 3.12+ (for Lambda packaging)
python3.12 --version

# Terraform (optional, for IaC approach)
terraform --version  # ≥ 1.0
```

### Required Secrets
Generate and store these securely (AWS Secrets Manager recommended):
```bash
# Billing internal key (32-byte random string)
openssl rand -base64 32

# JWT secret (if not already set)
openssl rand -base64 64

# Lago webhook secret
openssl rand -hex 32
```

---

## Infrastructure Setup

### 1. ElastiCache Redis

Deploy a Redis cluster for the cost ledger:

```bash
aws elasticache create-cache-cluster \
  --cache-cluster-id biomate-billing-redis \
  --cache-node-type cache.t4g.small \
  --engine redis \
  --engine-version 7.1 \
  --num-cache-nodes 1 \
  --cache-subnet-group-name biomate-private-subnets \
  --security-group-ids sg-XXXXXXXXX \
  --preferred-availability-zone us-west-2a \
  --port 6379 \
  --tags "Key=Service,Value=BioMate" "Key=Component,Value=Billing"
```

**Security Group Rules** (allow from BioMate EC2 + Lambda subnets):
```
Inbound: TCP 6379 from sg-biomate-app
Inbound: TCP 6379 from sg-biomate-lambda
```

**Retrieve endpoint**:
```bash
aws elasticache describe-cache-clusters \
  --cache-cluster-id biomate-billing-redis \
  --show-cache-node-info \
  --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' \
  --output text
```

### 2. Lambda Deployment

#### Option A: Bash Scripts (Quick Start)

```bash
cd /path/to/biomate/backend/lib/galaxy/ai/billing/infrastructure

# Deploy Batch event handler
./deploy_batch_lambda.sh us-west-2 123456789012

# Deploy S3 event handler
./deploy_s3_lambda.sh us-west-2 123456789012 biomate-nextflow-work
```

#### Option B: Terraform (Recommended for Production)

```bash
cd terraform/

# Initialize
terraform init

# Plan
terraform plan \
  -var="billing_api_url=http://biomate-internal-alb.us-west-2.elb.amazonaws.com:8081" \
  -var="billing_internal_key=$(aws secretsmanager get-secret-value --secret-id biomate/billing-key --query SecretString --output text)" \
  -var="redis_url=redis://biomate-billing-redis.abc123.0001.usw2.cache.amazonaws.com:6379/0"

# Apply
terraform apply
```

### 3. Update Lambda Environment Variables

After deployment, set the **real** environment variables (scripts use placeholders):

```bash
AWS_REGION="us-west-2"

# Batch Lambda
aws lambda update-function-configuration \
  --function-name biomate-batch-billing-handler \
  --environment "Variables={
    BILLING_API_URL=http://biomate-internal-alb.us-west-2.elb.amazonaws.com:8081,
    BILLING_INTERNAL_KEY=$(aws secretsmanager get-secret-value --secret-id biomate/billing-key --query SecretString --output text),
    REDIS_URL=redis://biomate-billing-redis.abc123.0001.usw2.cache.amazonaws.com:6379/0
  }" \
  --region "$AWS_REGION"

# S3 Lambda
aws lambda update-function-configuration \
  --function-name biomate-s3-billing-handler \
  --environment "Variables={
    BILLING_API_URL=http://biomate-internal-alb.us-west-2.elb.amazonaws.com:8081,
    BILLING_INTERNAL_KEY=$(aws secretsmanager get-secret-value --secret-id biomate/billing-key --query SecretString --output text),
    USER_TAG_NAME=user_id
  }" \
  --region "$AWS_REGION"
```

---

## Lago Setup

### 1. Deploy Lago (Docker)

**Option A: Standalone EC2**
```bash
# Launch t3.small EC2 instance with Docker installed
ssh ec2-user@lago-instance

# Create docker-compose.yml
cat > docker-compose.yml <<'EOF'
version: "3.9"
services:
  lago-db:
    image: postgres:15
    environment:
      POSTGRES_DB: lago
      POSTGRES_USER: lago
      POSTGRES_PASSWORD: CHANGE_ME
    volumes:
      - lago_pg:/var/lib/postgresql/data

  lago-redis:
    image: redis:7-alpine

  lago:
    image: getlago/lago:latest
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgres://lago:CHANGE_ME@lago-db:5432/lago
      REDIS_URL: redis://lago-redis:6379/1
      SECRET_KEY_BASE: $(openssl rand -hex 64)
      LAGO_RSA_PRIVATE_KEY: $(openssl genrsa 2048 | base64 -w 0)
      LAGO_API_URL: http://lago-internal-alb:3000
    depends_on:
      - lago-db
      - lago-redis

volumes:
  lago_pg:
EOF

# Start
docker-compose up -d
```

**Option B: AWS ECS/Fargate**
(Use the Terraform module from Lago's official repository)

### 2. Configure Billable Metrics

Access Lago UI at `http://lago-instance:3000` and create these metrics:

| Code | Name | Aggregation | Field Name | Unit |
|------|------|-------------|------------|------|
| `llm_input_tokens` | LLM Input Tokens | SUM | `tokens` | tokens |
| `llm_output_tokens` | LLM Output Tokens | SUM | `tokens` | tokens |
| `batch_vcpu_seconds` | Batch vCPU Seconds | SUM | `seconds` | vCPU·s |
| `batch_gpu_seconds` | Batch GPU Seconds | SUM | `seconds` | GPU·s |
| `batch_memory_gb_sec` | Batch Memory GB·s | SUM | `gb_seconds` | GB·s |
| `s3_storage_gb_hours` | S3 Storage | SUM | `gb_hours` | GB·hr |
| `s3_put_requests` | S3 PUT Requests | COUNT | `count` | reqs |
| `s3_get_requests` | S3 GET Requests | COUNT | `count` | reqs |
| `s3_data_transfer_gb` | S3 Data Transfer | SUM | `gb` | GB |

### 3. Create Plans

**Free Plan**:
- Monthly fee: $0
- LLM input: $0.25 / 1M tokens
- LLM output: $1.25 / 1M tokens
- Batch vCPU: $0.05 / 3600 seconds (= $0.05/vCPU-hour)
- Storage: $0.023 / 720 GB-hours (= $0.023/GB-month)

**Basic Plan** ($50/month):
- Same usage rates as Free
- Included credits: $50

**Pro Plan** ($200/month):
- 20% discount on all usage rates
- Included credits: $200

### 4. Register Webhook

In Lago UI → Settings → Webhooks:
- URL: `https://api.biomate.ai/webhooks/lago`
- Secret: (copy to `LAGO_WEBHOOK_SECRET` env var)

---

## Backend Integration

### 1. Set Environment Variables on BioMate Backend

Add to your EC2/ECS environment or `.env` file:

```bash
# Redis
REDIS_URL=redis://biomate-billing-redis.abc123.0001.usw2.cache.amazonaws.com:6379/0

# Lago
LAGO_API_URL=http://lago-internal-alb:3000
LAGO_API_KEY=<get from Lago UI → Settings → API Keys>
LAGO_WEBHOOK_SECRET=<32-byte hex string from Lago webhook config>

# Internal billing auth
BILLING_INTERNAL_KEY=<same key used in Lambda env vars>

# JWT (if not already set)
JWT_SECRET=<64-byte base64 string>
```

### 2. Verify Billing Router is Mounted

The billing router should already be wired into `fast_app.py` (completed in this session). Verify:

```bash
curl http://localhost:8081/openapi.json | jq '.paths | keys | .[] | select(contains("billing"))'
```

Expected output:
```
/api/billing/quota
/api/billing/usage
/api/billing/usage/history
/api/billing/jobs/running
/internal/billing/job_started
/internal/billing/job_completed
/internal/billing/s3_put
/internal/billing/s3_delete
/internal/billing/register_user
/internal/billing/add-credits
/internal/billing/admin/health
/internal/billing/admin/users
/webhooks/lago
```

### 3. Restart Backend

```bash
# If using systemd
sudo systemctl restart biomate-backend

# If using Docker
docker restart biomate-backend

# If using Gunicorn directly
pkill -HUP gunicorn
```

---

## Testing & Validation

### 1. Health Checks

```bash
# Backend alive
curl http://localhost:8081/api/version

# Billing router mounted
curl http://localhost:8081/api/billing/quota \
  -H "Authorization: Bearer test-user-123"  # Will fail auth but confirms routing

# Redis connectivity
redis-cli -h biomate-billing-redis.abc123.0001.usw2.cache.amazonaws.com ping
```

### 2. Lambda Function Tests

**Batch Lambda**:
```bash
# Trigger a test Batch job
aws batch submit-job \
  --job-name test-billing \
  --job-queue biomate-cpu-queue \
  --job-definition biomate-test:1 \
  --tags user_id=test-user,workflow_id=test-wf,instance_type=c6i.large,capacity_type=ON_DEMAND

# Check CloudWatch Logs
aws logs tail /aws/lambda/biomate-batch-billing-handler --follow
```

**S3 Lambda**:
```bash
# Upload a test file with tags
aws s3api put-object \
  --bucket biomate-nextflow-work \
  --key test/billing-test.txt \
  --body /tmp/test.txt \
  --tagging "user_id=test-user&workflow_id=test-wf"

# Check SQS queue
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-west-2.amazonaws.com/123456789012/biomate-s3-billing-events \
  --attribute-names ApproximateNumberOfMessages

# Check CloudWatch Logs
aws logs tail /aws/lambda/biomate-s3-billing-handler --follow
```

### 3. End-to-End Billing Flow

```bash
# 1. Register a test user
curl -X POST http://localhost:8081/internal/billing/register_user \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "test-user-001",
    "email": "test@biomate.ai",
    "name": "Test User",
    "plan": "free"
  }'

# 2. Submit a workflow (triggers Batch job with billing tags)
# (Use your normal workflow submission endpoint)

# 3. Wait 30s for job to start

# 4. Check real-time usage
curl http://localhost:8081/api/billing/usage \
  -H "Authorization: Bearer test-user-001" \
  | jq .

# 5. Verify Redis keys exist
redis-cli -h $REDIS_ENDPOINT KEYS "cost:test-user-001:*"

# 6. Check Lago received events
curl -X GET "$LAGO_API_URL/api/v1/customers/test-user-001/current_usage" \
  -H "Authorization: Bearer $LAGO_API_KEY" \
  | jq .
```

---

## Monitoring & Alerts

### 1. CloudWatch Alarms

```bash
# Lambda errors > 5/min
aws cloudwatch put-metric-alarm \
  --alarm-name biomate-batch-lambda-errors \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --period 60 \
  --statistic Sum \
  --threshold 5 \
  --dimensions Name=FunctionName,Value=biomate-batch-billing-handler

# SQS DLQ depth > 0
aws cloudwatch put-metric-alarm \
  --alarm-name biomate-s3-dlq-not-empty \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --metric-name ApproximateNumberOfMessagesVisible \
  --namespace AWS/SQS \
  --period 300 \
  --statistic Maximum \
  --threshold 0 \
  --dimensions Name=QueueName,Value=biomate-s3-billing-events-dlq
```

### 2. Admin Dashboard Access

```bash
# Health check
curl http://localhost:8081/internal/billing/admin/health \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  | jq .

# User spend summary
curl http://localhost:8081/internal/billing/admin/users \
  -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  | jq '.users | sort_by(.total_usd) | reverse | .[0:10]'
```

---

## Troubleshooting

### Issue: Lambda can't connect to Redis

**Symptoms**: CloudWatch logs show `redis.exceptions.ConnectionError`

**Fix**:
1. Ensure Lambda is in the same VPC as ElastiCache
2. Check security group allows port 6379
3. Verify `REDIS_URL` env var is correct

```bash
# Test from Lambda (via test event)
aws lambda invoke \
  --function-name biomate-batch-billing-handler \
  --payload '{"detail":{"jobId":"test"}}' \
  /tmp/lambda-out.json
```

### Issue: Batch jobs not generating billing events

**Symptoms**: EventBridge rule exists but Lambda never fires

**Fix**:
1. Check EventBridge rule pattern matches job status
2. Verify Lambda has permission from EventBridge
3. Check CloudWatch Logs for invocation errors

```bash
# List EventBridge rules
aws events list-rules --name-prefix biomate-batch

# Check rule targets
aws events list-targets-by-rule --rule biomate-batch-job-state-change
```

### Issue: S3 events not reaching Lambda

**Symptoms**: S3 uploads don't trigger billing

**Fix**:
1. Verify S3 bucket notification is configured
2. Check SQS queue policy allows S3
3. Check Lambda event source mapping is enabled

```bash
# Get bucket notification config
aws s3api get-bucket-notification-configuration --bucket biomate-nextflow-work

# Check SQS policy
aws sqs get-queue-attributes \
  --queue-url $SQS_URL \
  --attribute-names Policy
```

### Issue: Lago events rejected (HTTP 422)

**Symptoms**: Lambda logs show "Lago event rejected 422"

**Fix**:
1. Verify billable metric `code` matches Lago configuration exactly
2. Check `properties` field name matches metric config
3. Ensure customer exists in Lago

```bash
# List Lago billable metrics
curl "$LAGO_API_URL/api/v1/billable_metrics" \
  -H "Authorization: Bearer $LAGO_API_KEY" \
  | jq '.billable_metrics[].code'

# Check customer exists
curl "$LAGO_API_URL/api/v1/customers/test-user-001" \
  -H "Authorization: Bearer $LAGO_API_KEY"
```

---

## Rollback Plan

If critical issues arise:

1. **Disable Lambda triggers** (events still queue in SQS/EventBridge):
```bash
aws events disable-rule --name biomate-batch-job-state-change
aws lambda update-event-source-mapping --uuid $MAPPING_UUID --enabled=false
```

2. **Drain queued events** (after fix):
```bash
aws events enable-rule --name biomate-batch-job-state-change
aws lambda update-event-source-mapping --uuid $MAPPING_UUID --enabled=true
```

3. **Full rollback** (remove all billing infrastructure):
```bash
terraform destroy  # if using Terraform
# OR manually delete: Lambdas, EventBridge rule, SQS queues, IAM roles
```

---

## Post-Deployment Checklist

```
[ ] ElastiCache Redis deployed and accessible
[ ] Both Lambda functions deployed and environment variables set
[ ] EventBridge rule active and targeting Batch Lambda
[ ] S3 bucket notifications sending to SQS
[ ] SQS→Lambda event source mapping active
[ ] Lago deployed with all 9 billable metrics configured
[ ] Lago plans created (free, basic, pro)
[ ] Lago webhook registered and secret set
[ ] Backend environment variables set (REDIS_URL, LAGO_API_URL, LAGO_API_KEY, BILLING_INTERNAL_KEY)
[ ] Billing router mounted in FastAPI app
[ ] Health check endpoint returns 200
[ ] Test user registered successfully
[ ] Test workflow generates billing events
[ ] Real-time usage endpoint returns correct data
[ ] Lago customer_usage API shows events
[ ] CloudWatch alarms created
[ ] Monitoring dashboard configured
```

---

**Questions? Issues?**
Check the [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) for architecture details or file a ticket in the BioMate repo.
