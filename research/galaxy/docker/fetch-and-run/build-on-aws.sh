#!/bin/bash
set -e

echo "=========================================="
echo "AWS Docker Image Auto-Build Script"
echo "=========================================="
echo ""

# Configuration
REGION="us-west-2"
S3_BUCKET="galaxy-cloud-data-1760241377"
ECR_REPO="399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run"
IMAGE_TAG="latest"
INSTANCE_TYPE="t3.medium"
AMI_ID="ami-0735c191cf914754d"  # Amazon Linux 2 in us-west-2

# Get VPC and Subnet (use default)
echo "[1/6] Getting VPC and Subnet..."
VPC_ID=$(aws ec2 describe-vpcs --region $REGION --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
SUBNET_ID=$(aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0].SubnetId' --output text)

echo "  VPC: $VPC_ID"
echo "  Subnet: $SUBNET_ID"

# Create or get security group
echo "[2/6] Creating/Getting Security Group..."
SG_NAME="docker-build-temp-sg"
SG_ID=$(aws ec2 describe-security-groups --region $REGION --filters "Name=group-name,Values=$SG_NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")

if [ "$SG_ID" == "None" ]; then
    SG_ID=$(aws ec2 create-security-group \
        --group-name $SG_NAME \
        --description "Temporary SG for Docker builds" \
        --vpc-id $VPC_ID \
        --region $REGION \
        --query 'GroupId' \
        --output text)
    echo "  Created Security Group: $SG_ID"
else
    echo "  Using existing Security Group: $SG_ID"
fi

# Upload build files to S3
echo "[3/6] Uploading build files to S3..."
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
aws s3 cp "$SCRIPT_DIR/Dockerfile" s3://$S3_BUCKET/build/Dockerfile --region $REGION
aws s3 cp "$SCRIPT_DIR/fetch_and_run.sh" s3://$S3_BUCKET/build/fetch_and_run.sh --region $REGION
echo "  Files uploaded to s3://$S3_BUCKET/build/"

# Create UserData script
echo "[4/6] Preparing EC2 UserData script..."
cat > /tmp/userdata.sh <<'USERDATA_EOF'
#!/bin/bash

# Log everything to file AND S3
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Docker Build Script Started ==="
date

upload_status() {
    echo "$1" > /tmp/build-status.txt
    aws s3 cp /tmp/build-status.txt s3://BUCKET_PLACEHOLDER/build/build-status.txt --region REGION_PLACEHOLDER 2>/dev/null || true
    aws s3 cp /var/log/user-data.log s3://BUCKET_PLACEHOLDER/build/user-data.log --region REGION_PLACEHOLDER 2>/dev/null || true
}

trap 'upload_status "FAILED at line $LINENO"' ERR

upload_status "STARTED"

# Install Docker
echo "[1/6] Installing Docker..."
yum install -y docker
service docker start
upload_status "Docker installed"

# Download build files
echo "[2/6] Downloading build files from S3..."
mkdir -p /home/ec2-user/docker-build
cd /home/ec2-user/docker-build
aws s3 cp s3://BUCKET_PLACEHOLDER/build/Dockerfile . --region REGION_PLACEHOLDER
aws s3 cp s3://BUCKET_PLACEHOLDER/build/fetch_and_run.sh . --region REGION_PLACEHOLDER
chmod +x fetch_and_run.sh
upload_status "Files downloaded"

# Login to ECR
echo "[3/6] Logging in to ECR..."
aws ecr get-login-password --region REGION_PLACEHOLDER | docker login --username AWS --password-stdin ECR_REPO_PLACEHOLDER
upload_status "ECR login successful"

# Build image (this takes 20-30 minutes)
echo "[4/6] Building Docker image (this may take 20-30 minutes)..."
upload_status "Building Docker image..."
docker build --platform linux/amd64 -t galaxy-fetch-and-run:ab-full . 2>&1 | tee /tmp/docker-build.log
upload_status "Docker build complete"

# Tag and push
echo "[5/6] Tagging and pushing image..."
docker tag galaxy-fetch-and-run:ab-full ECR_REPO_PLACEHOLDER:IMAGE_TAG_PLACEHOLDER
docker push ECR_REPO_PLACEHOLDER:IMAGE_TAG_PLACEHOLDER 2>&1 | tee /tmp/docker-push.log
upload_status "Image pushed to ECR"

# Get digest
echo "[6/6] Getting image digest..."
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' ECR_REPO_PLACEHOLDER:IMAGE_TAG_PLACEHOLDER)
echo "Image pushed successfully!"
echo "Digest: $DIGEST"

# Upload digest and logs to S3
echo "$DIGEST" > /tmp/image-digest.txt
aws s3 cp /tmp/image-digest.txt s3://BUCKET_PLACEHOLDER/build/image-digest.txt --region REGION_PLACEHOLDER
aws s3 cp /tmp/docker-build.log s3://BUCKET_PLACEHOLDER/build/docker-build.log --region REGION_PLACEHOLDER 2>/dev/null || true
aws s3 cp /tmp/docker-push.log s3://BUCKET_PLACEHOLDER/build/docker-push.log --region REGION_PLACEHOLDER 2>/dev/null || true
upload_status "SUCCESS"

echo "=== Build Complete ==="
date

# Self-terminate instance after 5 minutes
echo "Instance will terminate in 5 minutes..."
sleep 300
shutdown -h now
USERDATA_EOF

# Replace placeholders
sed -i '' "s|BUCKET_PLACEHOLDER|$S3_BUCKET|g" /tmp/userdata.sh
sed -i '' "s|REGION_PLACEHOLDER|$REGION|g" /tmp/userdata.sh
sed -i '' "s|ECR_REPO_PLACEHOLDER|$ECR_REPO|g" /tmp/userdata.sh
sed -i '' "s|IMAGE_TAG_PLACEHOLDER|$IMAGE_TAG|g" /tmp/userdata.sh

# Launch EC2 instance
echo "[5/6] Launching EC2 instance for Docker build..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --subnet-id $SUBNET_ID \
    --security-group-ids $SG_ID \
    --iam-instance-profile Name=ecsInstanceRole \
    --user-data file:///tmp/userdata.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=docker-build-auto},{Key=Purpose,Value=temporary-build}]" \
    --region $REGION \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "  Instance launched: $INSTANCE_ID"
echo ""
echo "=========================================="
echo "Build in progress on AWS EC2..."
echo "=========================================="
echo ""
echo "Instance ID: $INSTANCE_ID"
echo "Monitoring build progress..."
echo ""

# Wait for instance to be running
echo "Waiting for instance to start..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION
echo "  Instance is running!"

# Get instance IP
INSTANCE_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --region $REGION \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)
echo "  Instance IP: $INSTANCE_IP"

# Monitor build progress
echo ""
echo "[6/6] Monitoring build progress (checking every 30 seconds)..."
echo "  Build logs will be available at: http://$INSTANCE_IP/var/log/user-data.log"
echo ""

for i in {1..20}; do
    echo "  Checking progress... ($i/20)"

    # Check if digest file exists in S3 (build complete)
    if aws s3 ls s3://$S3_BUCKET/build/image-digest.txt --region $REGION 2>/dev/null; then
        echo ""
        echo "=========================================="
        echo "✅ Build Complete!"
        echo "=========================================="

        # Download and display digest
        DIGEST=$(aws s3 cp s3://$S3_BUCKET/build/image-digest.txt - --region $REGION)
        echo "Image pushed to: $DIGEST"

        # Extract just the digest hash
        DIGEST_HASH=$(echo $DIGEST | grep -oE 'sha256:[a-f0-9]{64}')
        echo "Digest hash: $DIGEST_HASH"

        echo ""
        echo "Next steps:"
        echo "1. Update galaxy_job_runner.py with new digest:"
        echo "   $DIGEST_HASH"
        echo "2. Restart Galaxy"
        echo ""
        echo "Instance $INSTANCE_ID will auto-terminate in ~5 minutes"
        exit 0
    fi

    sleep 30
done

echo ""
echo "⚠️  Build taking longer than expected (>10 minutes)"
echo "Check instance logs manually:"
echo "  Instance ID: $INSTANCE_ID"
echo "  ssh ec2-user@$INSTANCE_IP"
echo "  tail -f /var/log/user-data.log"
echo ""
echo "Or wait and check S3 for digest file:"
echo "  aws s3 cp s3://$S3_BUCKET/build/image-digest.txt -"
