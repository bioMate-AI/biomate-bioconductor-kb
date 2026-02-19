#!/bin/bash
set -euo pipefail

# Deploy AWS Batch Event Handler Lambda
# Usage: ./deploy_batch_lambda.sh [AWS_REGION] [AWS_ACCOUNT_ID]

AWS_REGION="${1:-us-west-2}"
AWS_ACCOUNT_ID="${2:-$(aws sts get-caller-identity --query Account --output text)}"
LAMBDA_NAME="biomate-batch-billing-handler"
LAMBDA_ROLE_NAME="biomate-batch-billing-lambda-role"
EVENTBRIDGE_RULE_NAME="biomate-batch-job-state-change"

echo "==> Deploying Batch billing Lambda to region: $AWS_REGION"
echo "==> AWS Account: $AWS_ACCOUNT_ID"

# 1. Create IAM role if it doesn't exist
echo "==> Creating IAM role: $LAMBDA_ROLE_NAME"
if ! aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
  aws iam create-role \
    --role-name "$LAMBDA_ROLE_NAME" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "lambda.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }'

  # Attach policies
  aws iam attach-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"

  # Create inline policy for Batch access
  aws iam put-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-name "BatchDescribeJobs" \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Action": ["batch:DescribeJobs"],
        "Resource": "*"
      }]
    }'

  echo "==> Waiting 10s for IAM role propagation..."
  sleep 10
else
  echo "==> IAM role already exists"
fi

ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/$LAMBDA_ROLE_NAME"

# 2. Package Lambda code with dependencies
echo "==> Packaging Lambda code..."
cd "$(dirname "$0")/../lambda"
rm -rf package lambda_package.zip
mkdir -p package

# Install dependencies to package/
pip install -r 20260219_1545_lambda_requirements.txt -t package/ --quiet

# Copy handler code
cp batch_event_handler.py package/

# Create ZIP
cd package
zip -r ../lambda_package.zip . -q
cd ..

echo "==> Lambda package size: $(du -h lambda_package.zip | cut -f1)"

# 3. Create or update Lambda function
if aws lambda get-function --function-name "$LAMBDA_NAME" --region "$AWS_REGION" &>/dev/null; then
  echo "==> Updating Lambda function code..."
  aws lambda update-function-code \
    --function-name "$LAMBDA_NAME" \
    --zip-file fileb://lambda_package.zip \
    --region "$AWS_REGION" \
    --output text
else
  echo "==> Creating Lambda function..."
  aws lambda create-function \
    --function-name "$LAMBDA_NAME" \
    --runtime python3.12 \
    --role "$ROLE_ARN" \
    --handler batch_event_handler.handler \
    --zip-file fileb://lambda_package.zip \
    --timeout 30 \
    --memory-size 256 \
    --region "$AWS_REGION" \
    --environment "Variables={
      BILLING_API_URL=http://REPLACE_WITH_BIOMATE_INTERNAL_ALB:8081,
      BILLING_INTERNAL_KEY=REPLACE_WITH_SECRET,
      REDIS_URL=redis://REPLACE_WITH_ELASTICACHE_ENDPOINT:6379/0
    }" \
    --output text

  echo "==> Waiting 5s for Lambda creation..."
  sleep 5
fi

# 4. Create EventBridge rule
echo "==> Creating EventBridge rule: $EVENTBRIDGE_RULE_NAME"
aws events put-rule \
  --name "$EVENTBRIDGE_RULE_NAME" \
  --event-pattern '{
    "source": ["aws.batch"],
    "detail-type": ["Batch Job State Change"],
    "detail": {
      "status": ["RUNNING", "SUCCEEDED", "FAILED"]
    }
  }' \
  --state ENABLED \
  --region "$AWS_REGION" \
  --output text

# 5. Grant EventBridge permission to invoke Lambda
LAMBDA_ARN="arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:$LAMBDA_NAME"
STATEMENT_ID="AllowEventBridgeBatchEvents"

aws lambda add-permission \
  --function-name "$LAMBDA_NAME" \
  --statement-id "$STATEMENT_ID" \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn "arn:aws:events:$AWS_REGION:$AWS_ACCOUNT_ID:rule/$EVENTBRIDGE_RULE_NAME" \
  --region "$AWS_REGION" \
  --output text || echo "==> Permission already exists"

# 6. Add Lambda as EventBridge target
aws events put-targets \
  --rule "$EVENTBRIDGE_RULE_NAME" \
  --targets "Id=1,Arn=$LAMBDA_ARN" \
  --region "$AWS_REGION" \
  --output text

echo ""
echo "==> ✅ Batch billing Lambda deployed successfully!"
echo "==> Lambda ARN: $LAMBDA_ARN"
echo "==> EventBridge Rule: $EVENTBRIDGE_RULE_NAME"
echo ""
echo "==> ⚠️  IMPORTANT: Update Lambda environment variables:"
echo "    - BILLING_API_URL: Your internal BioMate API URL"
echo "    - BILLING_INTERNAL_KEY: Shared secret (same as backend BILLING_INTERNAL_KEY)"
echo "    - REDIS_URL: ElastiCache endpoint"
echo ""
echo "    aws lambda update-function-configuration \\"
echo "      --function-name $LAMBDA_NAME \\"
echo "      --environment 'Variables={BILLING_API_URL=http://your-alb:8081,BILLING_INTERNAL_KEY=your-key,REDIS_URL=redis://your-elasticache:6379/0}' \\"
echo "      --region $AWS_REGION"
echo ""
