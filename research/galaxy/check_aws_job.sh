#!/bin/bash
# Script to check AWS Batch job details

if [ -z "$1" ]; then
    echo "Usage: $0 <job-id>"
    echo ""
    echo "Recent jobs:"
    aws batch list-jobs --job-queue galaxy-cloud-queue --region us-west-2 --job-status SUCCEEDED FAILED RUNNING RUNNABLE --max-items 10 --output table --query 'jobSummaryList[*].[jobId,jobName,status,createdAt,startedAt,stoppedAt]'
    exit 1
fi

JOB_ID="$1"

echo "=== Job Details ==="
aws batch describe-jobs --jobs "$JOB_ID" --region us-west-2 \
    --query 'jobs[0].[jobName,status,container.exitCode,container.reason]' \
    --output table

echo ""
echo "=== Container Command ==="
aws batch describe-jobs --jobs "$JOB_ID" --region us-west-2 \
    --query 'jobs[0].container.command' \
    --output json

echo ""
echo "=== Job Timing ==="
aws batch describe-jobs --jobs "$JOB_ID" --region us-west-2 \
    --query 'jobs[0].[createdAt,startedAt,stoppedAt]' \
    --output table

echo ""
echo "=== CloudWatch Logs ==="
LOG_STREAM=$(aws batch describe-jobs --jobs "$JOB_ID" --region us-west-2 \
    --query 'jobs[0].container.logStreamName' --output text)

if [ "$LOG_STREAM" != "None" ] && [ -n "$LOG_STREAM" ]; then
    echo "Log stream: $LOG_STREAM"
    echo ""
    aws logs get-log-events \
        --log-group-name /aws/batch/job \
        --log-stream-name "$LOG_STREAM" \
        --region us-west-2 \
        --query 'events[*].message' \
        --output text | head -50
else
    echo "No logs available yet"
fi
