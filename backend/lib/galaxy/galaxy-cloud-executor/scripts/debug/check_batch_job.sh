#!/bin/bash
# 检查AWS Batch Job详情

JOB_ID="${1:-719d2183-52fe-43c3-9b84-62f649e7bd84}"

echo "========================================"
echo "AWS Batch Job详情"
echo "========================================"
echo "Job ID: $JOB_ID"
echo ""

# 获取job详情
aws batch describe-jobs --jobs "$JOB_ID" --output json > /tmp/job_detail.json

# 显示job状态
echo "Job状态:"
cat /tmp/job_detail.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data.get('jobs'):
    job = data['jobs'][0]
    print(f\"  Status: {job.get('status', 'UNKNOWN')}\")
    print(f\"  Status Reason: {job.get('statusReason', 'N/A')}\")
    print(f\"  Container Exit Code: {job.get('container', {}).get('exitCode', 'N/A')}\")
    print(f\"  Container Reason: {job.get('container', {}).get('reason', 'N/A')}\")
    print(f\"  Job Queue: {job.get('jobQueue', 'N/A')}\")
    print(f\"  Job Definition: {job.get('jobDefinition', 'N/A')}\")
    
    # 显示容器详情
    container = job.get('container', {})
    if container:
        print(f\"\nContainer详情:\")
        print(f\"  Image: {container.get('image', 'N/A')}\")
        print(f\"  Command: {container.get('command', 'N/A')}\")
        print(f\"  Log Stream: {container.get('logStreamName', 'N/A')}\")
else:
    print('  Job not found!')
"

echo ""
echo "完整JSON (保存在 /tmp/job_detail.json):"
cat /tmp/job_detail.json | python3 -m json.tool
