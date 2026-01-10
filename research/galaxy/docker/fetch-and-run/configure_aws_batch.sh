#!/bin/bash
#
# Configure AWS Batch for Galaxy Fetch-and-Run with Docker-in-Docker support
#

set -e

# Configuration
AWS_REGION="us-west-2"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_IMAGE="399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest"
JOB_DEFINITION_NAME="galaxy-fetch-and-run"
JOB_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/BatchJobRole"
EXECUTION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole"

echo "========================================="
echo "Configuring AWS Batch for Fetch-and-Run"
echo "========================================="
echo "AWS Region: ${AWS_REGION}"
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "ECR Image: ${ECR_IMAGE}"
echo "Job Definition: ${JOB_DEFINITION_NAME}"
echo "========================================="

# Check if roles exist
echo "[1/2] Checking IAM roles..."
if aws iam get-role --role-name BatchJobRole --region ${AWS_REGION} >/dev/null 2>&1; then
    echo "✓ BatchJobRole exists"
else
    echo "⚠ BatchJobRole not found - you'll need to create it or update JOB_ROLE_ARN"
fi

if aws iam get-role --role-name ecsTaskExecutionRole --region ${AWS_REGION} >/dev/null 2>&1; then
    echo "✓ ecsTaskExecutionRole exists"
else
    echo "⚠ ecsTaskExecutionRole not found - you'll need to create it or update EXECUTION_ROLE_ARN"
fi

# Create job definition with Docker-in-Docker support
echo "[2/2] Creating AWS Batch job definition..."

cat > /tmp/job-definition.json <<EOF
{
  "jobDefinitionName": "${JOB_DEFINITION_NAME}",
  "type": "container",
  "platformCapabilities": ["EC2"],
  "containerProperties": {
    "image": "${ECR_IMAGE}",
    "vcpus": 2,
    "memory": 4096,
    "privileged": true,
    "volumes": [
      {
        "host": {
          "sourcePath": "/var/run/docker.sock"
        },
        "name": "docker-socket"
      }
    ],
    "mountPoints": [
      {
        "containerPath": "/var/run/docker.sock",
        "sourceVolume": "docker-socket",
        "readOnly": false
      }
    ],
    "jobRoleArn": "${JOB_ROLE_ARN}",
    "executionRoleArn": "${EXECUTION_ROLE_ARN}",
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {}
    },
    "linuxParameters": {
      "initProcessEnabled": true
    }
  },
  "retryStrategy": {
    "attempts": 2
  },
  "timeout": {
    "attemptDurationSeconds": 3600
  }
}
EOF

# Register the job definition
aws batch register-job-definition \
    --cli-input-json file:///tmp/job-definition.json \
    --region ${AWS_REGION}

echo "✓ Job definition created successfully"

# Get the revision number
REVISION=$(aws batch describe-job-definitions \
    --job-definition-name ${JOB_DEFINITION_NAME} \
    --status ACTIVE \
    --region ${AWS_REGION} \
    --query 'jobDefinitions[0].revision' \
    --output text)

echo ""
echo "========================================="
echo "Configuration Complete!"
echo "========================================="
echo "Job Definition: ${JOB_DEFINITION_NAME}:${REVISION}"
echo ""
echo "⚠ IMPORTANT: This job definition requires:"
echo "  1. Privileged mode (enabled)"
echo "  2. Docker socket mounted (configured)"
echo "  3. EC2-based compute environment (not Fargate)"
echo ""
echo "Next steps:"
echo "  1. Ensure your compute environment uses EC2 instances"
echo "  2. Update Galaxy job_conf.yml to use fetch-and-run mode"
echo "  3. Test with a simple workflow"
echo "========================================="

# Clean up
rm /tmp/job-definition.json
