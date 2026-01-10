#!/usr/bin/env python3
import sys
import json
import subprocess

if len(sys.argv) < 2:
    print("Usage: python3 get_aws_logs.py <job-id>")
    sys.exit(1)

job_id = sys.argv[1]

# Get job details to find log stream
result = subprocess.run(
    [
        "aws", "batch", "describe-jobs",
        "--jobs", job_id,
        "--region", "us-west-2",
        "--output", "json"
    ],
    capture_output=True,
    text=True
)

if result.returncode != 0:
    print(f"Error describing job: {result.stderr}")
    sys.exit(1)

job_data = json.loads(result.stdout)
if not job_data.get('jobs'):
    print(f"Job {job_id} not found")
    sys.exit(1)

job = job_data['jobs'][0]
log_stream = job.get('container', {}).get('logStreamName')

if not log_stream:
    print(f"No log stream found for job {job_id}")
    print(f"Job status: {job.get('status')}")
    sys.exit(1)

print(f"Log stream: {log_stream}\n")

# Get logs
result = subprocess.run(
    [
        "aws", "logs", "get-log-events",
        "--log-group-name", "/aws/batch/job",
        "--log-stream-name", log_stream,
        "--region", "us-west-2",
        "--start-from-head",
        "--no-paginate",
        "--output", "json"
    ],
    capture_output=True,
    text=True,
    env={**subprocess.os.environ, "PYTHONIOENCODING": "utf-8"}
)

if result.returncode != 0:
    print(f"Error getting logs: {result.stderr}")
    sys.exit(1)

try:
    logs_data = json.loads(result.stdout)
    for event in logs_data.get('events', []):
        print(event['message'])
except json.JSONDecodeError as e:
    print(f"Error parsing JSON: {e}")
    print("Raw output:")
    print(result.stdout[:1000])
