# Fetch-and-Run Docker-in-Docker Deployment Guide

## Overview

This guide explains how to build, deploy, and configure the Galaxy fetch-and-run wrapper container with Docker-in-Docker (DinD) support for AWS Batch.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ AWS Batch Job (fetch-and-run wrapper container)            │
│                                                             │
│  1. Download inputs from S3                                │
│  2. Download job script from S3                            │
│  3. Execute job in one of two modes:                       │
│                                                             │
│     Mode A: Docker-in-Docker (when tool container exists)  │
│     ┌───────────────────────────────────────┐             │
│     │ Tool Container (e.g., BioContainer)   │             │
│     │  - Isolated execution environment     │             │
│     │  - Runs job script with Galaxy tool   │             │
│     └───────────────────────────────────────┘             │
│                                                             │
│     Mode B: Direct Execution (when no tool container)     │
│     - Runs job script directly in wrapper container       │
│                                                             │
│  4. Upload outputs to S3                                   │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **AWS Account** with permissions for:
   - ECR (Elastic Container Registry)
   - Batch (AWS Batch)
   - S3 (Simple Storage Service)
   - IAM (Identity and Access Management)

2. **AWS CLI** configured with credentials:
   ```bash
   aws configure
   ```

3. **Docker** installed locally for building images

4. **Galaxy** with galaxy-cloud-executor configured

## Step 1: Build and Push the Fetch-and-Run Image

### 1.1 Navigate to the fetch-and-run directory

```bash
cd /Users/renyuankai/work/biometa/galaxy/docker/fetch-and-run
```

### 1.2 Configure the build script

Edit `build_and_push.sh` if needed to change:
- AWS region (default: `us-west-2`)
- Image name (default: `galaxy-fetch-and-run`)
- Image tag (default: `latest`)

### 1.3 Run the build and push script

```bash
chmod +x build_and_push.sh
./build_and_push.sh
```

This script will:
1. Build the Docker image with AWS CLI, Docker client, and fetch_and_run.sh
2. Create an ECR repository (if it doesn't exist)
3. Tag the image for ECR
4. Push the image to ECR

### 1.4 Note the ECR image URI

The script will output the full ECR image URI, for example:
```
123456789012.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest
```

Save this URI - you'll need it for configuration.

## Step 2: Configure AWS Batch for Docker-in-Docker

For Docker-in-Docker to work, AWS Batch jobs need access to the Docker daemon. There are two approaches:

### Approach A: Privileged Mode (Recommended for Testing)

**Update your AWS Batch Job Definition** to enable privileged mode:

```json
{
  "jobDefinitionName": "galaxy-fetch-and-run-job",
  "type": "container",
  "containerProperties": {
    "image": "123456789012.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest",
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
        "sourceVolume": "docker-socket"
      }
    ],
    "jobRoleArn": "arn:aws:iam::123456789012:role/BatchJobRole",
    "executionRoleArn": "arn:aws:iam::123456789012:role/BatchExecutionRole"
  }
}
```

**Important**: The `privileged: true` flag is required for Docker-in-Docker to work.

### Approach B: Docker-in-Docker Daemon (Production)

For production environments, consider running a DinD daemon sidecar:

```json
{
  "jobDefinitionName": "galaxy-fetch-and-run-job-dind",
  "type": "container",
  "containerProperties": {
    "image": "123456789012.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest",
    "vcpus": 2,
    "memory": 4096,
    "linuxParameters": {
      "initProcessEnabled": true
    },
    "dependsOn": [
      {
        "containerName": "dind",
        "condition": "START"
      }
    ]
  },
  "sidecars": [
    {
      "name": "dind",
      "image": "docker:dind",
      "essential": true,
      "privileged": true,
      "environment": [
        {"name": "DOCKER_TLS_CERTDIR", "value": ""}
      ]
    }
  ]
}
```

## Step 3: Configure Galaxy Job Runner

### 3.1 Update Galaxy job configuration

Edit `config/job_conf.yml`:

```yaml
execution:
  default: cloud_fetch_and_run
  environments:
    cloud_fetch_and_run:
      runner: galaxy_cloud
      params:
        # Enable fetch-and-run mode
        use_fetch_and_run: true

        # AWS Configuration
        provider: aws
        aws_region: us-west-2
        aws_batch_queue: galaxy-cloud-queue
        aws_s3_bucket: galaxy-cloud-data-1760241377

        # Fetch-and-Run Image
        fetch_and_run_image: "123456789012.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest"

        # Resource limits
        cpus: 2
        memory: 4  # GB
        disk: 20   # GB
```

### 3.2 Ensure tool containers are configured

Edit `config/tool_containers.json` to map Galaxy tools to BioContainers:

```json
{
  "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.72": {
    "image": "quay.io/biocontainers/fastqc:0.11.9--0",
    "verified": true
  },
  "toolshed.g2.bx.psu.edu/repos/iuc/collection_element_identifiers/collection_element_identifiers/0.0.2": {
    "image": "quay.io/biocontainers/python:3.9",
    "verified": true
  }
}
```

**Important**: If a tool doesn't have a container configured, the job will run directly in the fetch-and-run wrapper container (which has Python 3 and basic utilities).

## Step 4: Test the Deployment

### 4.1 Start Galaxy

```bash
cd /Users/renyuankai/work/biometa/galaxy
./run.sh
```

### 4.2 Run a test workflow

1. Upload test data to Galaxy
2. Run a workflow with tools that have container mappings
3. Monitor job execution

### 4.3 Check AWS Batch logs

View logs in AWS CloudWatch for the job:

```bash
# Get the job ID from Galaxy logs
JOB_ID="abc123"

# Find the AWS Batch job
aws batch describe-jobs --jobs galaxy-${JOB_ID}

# Get the log stream
aws logs get-log-events \
  --log-group-name /aws/batch/job \
  --log-stream-name galaxy-${JOB_ID}/default/...
```

Expected log output:
```
=========================================
Galaxy Fetch-and-Run Starting
=========================================
Job ID: 196
S3 Bucket: galaxy-cloud-data-1760241377
AWS Region: us-west-2
Tool Container: quay.io/biocontainers/fastqc:0.11.9--0
=========================================

[1/4] Downloading job script from S3...
✓ Job script downloaded successfully

[2/4] Downloading input files from S3...
✓ Downloaded 2 input file(s)

[3/4] Executing job script...
Running in Docker-in-Docker mode with image: quay.io/biocontainers/fastqc:0.11.9--0
Pulling tool container image...
latest: Pulling from biocontainers/fastqc
...

[4/4] Uploading output files to S3...
✓ Uploaded 1 output file(s)

=========================================
Galaxy Fetch-and-Run Completed Successfully
=========================================
```

## Step 5: Troubleshooting

### Problem: "Docker not found" error

**Error**:
```
ERROR: Docker not found, but TOOL_CONTAINER_IMAGE is set
```

**Solution**: Ensure the fetch-and-run image was built with Docker client installed:
```bash
# Check the Dockerfile includes docker in yum install
cat Dockerfile | grep docker
```

### Problem: "Permission denied" when accessing Docker socket

**Error**:
```
Got permission denied while trying to connect to the Docker daemon socket
```

**Solution**: Ensure the AWS Batch job definition has `privileged: true` set.

### Problem: Tool container fails to pull

**Error**:
```
⚠ Failed to pull image, trying to use cached version...
```

**Solution**:
1. Check the container image exists and is accessible
2. Verify the AWS Batch compute environment has internet access
3. If using private registry, ensure IAM role has pull permissions

### Problem: "No command line available" error

**Error**:
```
ValueError: No command line available for job 196
```

**Solution**: This should be fixed in the latest code. If you still see it:
1. Check that the tool is properly configured in Galaxy
2. Verify the tool XML has a valid `<command>` section
3. Check Galaxy logs for tool preparation errors

### Problem: Dataset state warnings (paused/discarded)

**Warning**:
```
WARNING galaxy.model Failed to determine file name for dataset 313 in state paused
```

**Solution**: These are from previous failed runs. Clean up:
```bash
# Stop Galaxy
./run.sh --stop

# Clean up database (CAREFUL - this deletes data)
# Only do this in dev/test environments
python scripts/cleanup_datasets/cleanup_datasets.py

# Restart Galaxy
./run.sh
```

## Step 6: Production Considerations

### 6.1 Security

- **Use IAM roles** for AWS credentials, not access keys
- **Enable VPC** for AWS Batch compute environment
- **Restrict S3 bucket access** to only the batch job role
- **Use private ECR** for fetch-and-run image
- **Scan containers** for vulnerabilities before deployment

### 6.2 Performance

- **Pre-pull tool containers** to reduce startup time:
  ```bash
  # Add to compute environment user data
  docker pull quay.io/biocontainers/fastqc:0.11.9--0
  ```

- **Use EFS** for shared reference data instead of S3 downloads

- **Optimize S3 transfers** with parallelization:
  ```bash
  aws configure set default.s3.max_concurrent_requests 20
  ```

### 6.3 Monitoring

- **Enable CloudWatch metrics** for AWS Batch
- **Set up alarms** for job failures
- **Track S3 costs** with bucket analytics
- **Monitor ECR storage** and implement image lifecycle policies

### 6.4 Cost Optimization

- **Use Spot instances** for non-critical workloads
- **Implement S3 lifecycle policies** to archive old job data
- **Right-size resources** - don't over-provision CPU/memory
- **Clean up failed jobs** to avoid storage costs

## Architecture Notes

### Why Docker-in-Docker?

Docker-in-Docker allows us to:
1. **Use any BioContainer** without modification
2. **Isolate tool execution** from the wrapper environment
3. **Match Galaxy's local execution** behavior exactly
4. **Avoid complex container building** for each tool

### Alternative: Direct Execution Mode

If a tool doesn't have a container configured, the fetch-and-run wrapper will execute the job script directly. This works for tools that only need:
- Python 3
- Basic Unix utilities (bash, tar, gzip, etc.)
- AWS CLI

For example, simple data manipulation tools or Python scripts can run without Docker-in-Docker overhead.

## Next Steps

1. **Monitor first few workflow runs** carefully
2. **Optimize resource allocation** based on actual usage
3. **Add more tool containers** to `config/tool_containers.json`
4. **Consider EFS mounting** for reference genomes
5. **Implement job retry logic** for transient failures

## Support

For issues or questions:
1. Check Galaxy logs: `tail -f galaxy.log`
2. Check AWS Batch logs: CloudWatch Logs
3. Review S3 bucket contents: `aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/`
4. Check this documentation and README files

## References

- [AWS Batch Best Practices](https://docs.aws.amazon.com/batch/latest/userguide/best-practices.html)
- [Docker-in-Docker Documentation](https://hub.docker.com/_/docker)
- [Galaxy Tool Containers](https://galaxyproject.org/admin/tools/containers/)
- [BioContainers Registry](https://biocontainers.pro/)
