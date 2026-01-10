#!/bin/bash
#
# Fix IAM permissions for fetch-and-run jobs
#

set -e

AWS_REGION="us-west-2"
S3_BUCKET="galaxy-cloud-data-1760241377"
JOB_ROLE="BatchJobRole"

echo "========================================="
echo "Fixing IAM Permissions for Fetch-and-Run"
echo "========================================="
echo "S3 Bucket: ${S3_BUCKET}"
echo "Job Role: ${JOB_ROLE}"
echo "========================================="

# Test current permissions
echo "[1/3] Testing current S3 permissions..."
TEST_KEY="test-permissions-$(date +%s).txt"

# Try to write to S3 using the role (this simulates what the container does)
echo "Testing write access..."
echo "test" | aws s3 cp - "s3://${S3_BUCKET}/test/${TEST_KEY}" --region ${AWS_REGION} 2>&1 || echo "⚠ Write test failed"

echo "Testing read access..."
aws s3 cp "s3://${S3_BUCKET}/test/${TEST_KEY}" - --region ${AWS_REGION} 2>&1 || echo "⚠ Read test failed"

# Clean up test file
aws s3 rm "s3://${S3_BUCKET}/test/${TEST_KEY}" --region ${AWS_REGION} 2>/dev/null || true

echo ""
echo "[2/3] Checking IAM role trust relationship..."

# Check if the role can be assumed by ECS tasks
TRUST_POLICY=$(aws iam get-role --role-name ${JOB_ROLE} --query 'Role.AssumeRolePolicyDocument' --output json)
echo "$TRUST_POLICY" | jq .

# Verify that ecs-tasks.amazonaws.com is in the trust policy
if echo "$TRUST_POLICY" | grep -q "ecs-tasks.amazonaws.com"; then
    echo "✓ ECS tasks can assume this role"
else
    echo "⚠ WARNING: ECS tasks may not be able to assume this role"
    echo "Adding ecs-tasks.amazonaws.com to trust policy..."

    # Create updated trust policy
    cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ecs-tasks.amazonaws.com",
          "batch.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    aws iam update-assume-role-policy \
        --role-name ${JOB_ROLE} \
        --policy-document file:///tmp/trust-policy.json

    echo "✓ Trust policy updated"
    rm /tmp/trust-policy.json
fi

echo ""
echo "[3/3] Verifying S3 policy..."

# Get current S3 policy
POLICY_ARN=$(aws iam list-attached-role-policies --role-name ${JOB_ROLE} --query 'AttachedPolicies[?PolicyName==`BatchJobS3Access`].PolicyArn' --output text)

if [ -z "$POLICY_ARN" ]; then
    echo "⚠ BatchJobS3Access policy not found, creating..."

    # Create the policy
    cat > /tmp/s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET}",
        "arn:aws:s3:::${S3_BUCKET}/*"
      ]
    }
  ]
}
EOF

    POLICY_ARN=$(aws iam create-policy \
        --policy-name BatchJobS3Access \
        --policy-document file:///tmp/s3-policy.json \
        --query 'Policy.Arn' \
        --output text)

    aws iam attach-role-policy \
        --role-name ${JOB_ROLE} \
        --policy-arn ${POLICY_ARN}

    echo "✓ Policy created and attached"
    rm /tmp/s3-policy.json
else
    echo "✓ S3 policy is attached: ${POLICY_ARN}"

    # Show the policy
    POLICY_VERSION=$(aws iam get-policy --policy-arn ${POLICY_ARN} --query 'Policy.DefaultVersionId' --output text)
    echo "Policy content:"
    aws iam get-policy-version --policy-arn ${POLICY_ARN} --version-id ${POLICY_VERSION} --query 'PolicyVersion.Document' --output json | jq .
fi

echo ""
echo "========================================="
echo "Diagnostics Complete"
echo "========================================="
echo ""
echo "If you're still seeing 403 errors, the issue might be:"
echo "  1. IAM role propagation delay (wait 1-2 minutes)"
echo "  2. S3 bucket policy blocking access"
echo "  3. Container not picking up IAM credentials"
echo ""
echo "To debug further, check the container logs for:"
echo "  - AWS_CONTAINER_CREDENTIALS_RELATIVE_URI environment variable"
echo "  - aws sts get-caller-identity output"
echo ""
echo "Next steps:"
echo "  1. Wait 1-2 minutes for IAM changes to propagate"
echo "  2. Re-run your Galaxy workflow"
echo "  3. Check AWS Batch container logs"
echo "========================================="
