#!/bin/bash
set -euo pipefail

# Deploy S3 Event Handler Lambda
# Usage: ./deploy_s3_lambda.sh [AWS_REGION] [AWS_ACCOUNT_ID] [S3_BUCKET_NAME]

AWS_REGION="${1:-us-west-2}"
AWS_ACCOUNT_ID="${2:-$(aws sts get-caller-identity --query Account --output text)}"
S3_BUCKET="${3:-biomate-nextflow-work}"
LAMBDA_NAME="biomate-s3-billing-handler"
LAMBDA_ROLE_NAME="biomate-s3-billing-lambda-role"
SQS_QUEUE_NAME="biomate-s3-billing-events"
DLQ_NAME="biomate-s3-billing-events-dlq"

echo "==> Deploying S3 billing Lambda to region: $AWS_REGION"
echo "==> AWS Account: $AWS_ACCOUNT_ID"
echo "==> S3 Bucket: $S3_BUCKET"

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

  # Attach basic execution policy
  aws iam attach-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

  # Create inline policy for S3 + SQS access
  aws iam put-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-name "S3AndSQSAccess" \
    --policy-document "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [
        {
          \"Effect\": \"Allow\",
          \"Action\": [\"s3:GetObjectTagging\", \"s3:HeadObject\"],
          \"Resource\": \"arn:aws:s3:::$S3_BUCKET/*\"
        },
        {
          \"Effect\": \"Allow\",
          \"Action\": [
            \"sqs:ReceiveMessage\",
            \"sqs:DeleteMessage\",
            \"sqs:GetQueueAttributes\"
          ],
          \"Resource\": \"arn:aws:sqs:$AWS_REGION:$AWS_ACCOUNT_ID:$SQS_QUEUE_NAME\"
        }
      ]
    }"

  echo "==> Waiting 10s for IAM role propagation..."
  sleep 10
else
  echo "==> IAM role already exists"
fi

ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/$LAMBDA_ROLE_NAME"

# 2. Create DLQ
echo "==> Creating SQS DLQ: $DLQ_NAME"
DLQ_URL=$(aws sqs create-queue \
  --queue-name "$DLQ_NAME" \
  --region "$AWS_REGION" \
  --output text --query 'QueueUrl' 2>/dev/null || \
  aws sqs get-queue-url --queue-name "$DLQ_NAME" --region "$AWS_REGION" --output text --query 'QueueUrl')

DLQ_ARN="arn:aws:sqs:$AWS_REGION:$AWS_ACCOUNT_ID:$DLQ_NAME"

# 3. Create main SQS queue with DLQ
echo "==> Creating SQS queue: $SQS_QUEUE_NAME"
SQS_URL=$(aws sqs create-queue \
  --queue-name "$SQS_QUEUE_NAME" \
  --attributes "{
    \"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"
  }" \
  --region "$AWS_REGION" \
  --output text --query 'QueueUrl' 2>/dev/null || \
  aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --region "$AWS_REGION" --output text --query 'QueueUrl')

SQS_ARN="arn:aws:sqs:$AWS_REGION:$AWS_ACCOUNT_ID:$SQS_QUEUE_NAME"

# 4. Grant S3 permission to send to SQS
echo "==> Granting S3 permission to send to SQS..."
aws sqs set-queue-attributes \
  --queue-url "$SQS_URL" \
  --attributes "{
    \"Policy\": \"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[{\\\"Effect\\\":\\\"Allow\\\",\\\"Principal\\\":{\\\"Service\\\":\\\"s3.amazonaws.com\\\"},\\\"Action\\\":\\\"SQS:SendMessage\\\",\\\"Resource\\\":\\\"$SQS_ARN\\\",\\\"Condition\\\":{\\\"StringEquals\\\":{\\\"aws:SourceAccount\\\":\\\"$AWS_ACCOUNT_ID\\\"},\\\"ArnLike\\\":{\\\"aws:SourceArn\\\":\\\"arn:aws:s3:::$S3_BUCKET\\\"}}}]}\"
  }" \
  --region "$AWS_REGION"

# 5. Configure S3 bucket notifications
echo "==> Configuring S3 bucket notifications..."
aws s3api put-bucket-notification-configuration \
  --bucket "$S3_BUCKET" \
  --notification-configuration "{
    \"QueueConfigurations\": [{
      \"QueueArn\": \"$SQS_ARN\",
      \"Events\": [\"s3:ObjectCreated:*\", \"s3:ObjectRemoved:*\"]
    }]
  }" \
  --region "$AWS_REGION"

# 6. Package Lambda code
echo "==> Packaging Lambda code..."
cd "$(dirname "$0")/../lambda"
rm -rf package lambda_package_s3.zip
mkdir -p package

pip install -r 20260219_1545_lambda_requirements.txt -t package/ --quiet
cp s3_event_handler.py package/

cd package
zip -r ../lambda_package_s3.zip . -q
cd ..

echo "==> Lambda package size: $(du -h lambda_package_s3.zip | cut -f1)"

# 7. Create or update Lambda function
if aws lambda get-function --function-name "$LAMBDA_NAME" --region "$AWS_REGION" &>/dev/null; then
  echo "==> Updating Lambda function code..."
  aws lambda update-function-code \
    --function-name "$LAMBDA_NAME" \
    --zip-file fileb://lambda_package_s3.zip \
    --region "$AWS_REGION" \
    --output text
else
  echo "==> Creating Lambda function..."
  aws lambda create-function \
    --function-name "$LAMBDA_NAME" \
    --runtime python3.12 \
    --role "$ROLE_ARN" \
    --handler s3_event_handler.handler \
    --zip-file fileb://lambda_package_s3.zip \
    --timeout 30 \
    --memory-size 256 \
    --region "$AWS_REGION" \
    --environment "Variables={
      BILLING_API_URL=http://REPLACE_WITH_BIOMATE_INTERNAL_ALB:8081,
      BILLING_INTERNAL_KEY=REPLACE_WITH_SECRET,
      USER_TAG_NAME=user_id
    }" \
    --output text

  echo "==> Waiting 5s for Lambda creation..."
  sleep 5
fi

LAMBDA_ARN="arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:$LAMBDA_NAME"

# 8. Create SQS → Lambda event source mapping
echo "==> Creating SQS trigger for Lambda..."
aws lambda create-event-source-mapping \
  --function-name "$LAMBDA_NAME" \
  --event-source-arn "$SQS_ARN" \
  --batch-size 10 \
  --region "$AWS_REGION" \
  --output text 2>/dev/null || echo "==> Event source mapping already exists"

echo ""
echo "==> ✅ S3 billing Lambda deployed successfully!"
echo "==> Lambda ARN: $LAMBDA_ARN"
echo "==> SQS Queue: $SQS_URL"
echo "==> DLQ: $DLQ_URL"
echo ""
echo "==> ⚠️  IMPORTANT: Update Lambda environment variables:"
echo "    - BILLING_API_URL: Your internal BioMate API URL"
echo "    - BILLING_INTERNAL_KEY: Shared secret"
echo ""
echo "    aws lambda update-function-configuration \\"
echo "      --function-name $LAMBDA_NAME \\"
echo "      --environment 'Variables={BILLING_API_URL=http://your-alb:8081,BILLING_INTERNAL_KEY=your-key,USER_TAG_NAME=user_id}' \\"
echo "      --region $AWS_REGION"
echo ""
