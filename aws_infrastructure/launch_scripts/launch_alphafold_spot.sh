#!/bin/bash
set -e

# ============================================================================
# Launch AlphaFold 3 Spot Instance for BioMate Benchmark Testing
# ============================================================================
# Instance: g5.12xlarge (48 vCPU, 192GB RAM, 4x NVIDIA A10G GPUs)
# Purpose: Run AlphaFold 3 predictions via BioMate Nextflow orchestration
# Cost: ~$3-4/hour (spot), max budget $20 (5-6 hours max)
# ============================================================================

# Configuration
REGION="us-east-1"
INSTANCE_TYPE="g5.12xlarge"
AMI_ID="ami-0c7217cdde317cfec"  # Ubuntu 22.04 with NVIDIA drivers
KEY_NAME="cryosparc-benchmark"
SECURITY_GROUP="sg-015137721b5fabddb"
MAX_SPOT_PRICE="5.00"  # Safety limit

# Execution metadata
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_ID="biomate_alphafold_${TIMESTAMP}"
OUTPUT_DIR="$HOME/biomate/aws_infrastructure/runs/${RUN_ID}"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}================================================"
echo "BioMate AlphaFold 3 Benchmark - Launch Spot Instance"
echo "================================================${NC}"
echo "Run ID: ${RUN_ID}"
echo "Instance: ${INSTANCE_TYPE}"
echo "Region: ${REGION}"
echo "Max Spot Price: \$${MAX_SPOT_PRICE}/hour"
echo ""

# Create output directory
mkdir -p "${OUTPUT_DIR}"
cd "${OUTPUT_DIR}"

# Log all output
exec > >(tee -a launch.log)
exec 2>&1

# Validate prerequisites
echo -e "${YELLOW}[1/7] Validating prerequisites...${NC}"
if [ ! -f "$HOME/.ssh/cryosparc-benchmark.pem" ]; then
    echo -e "${RED}ERROR: SSH key not found at ~/.ssh/cryosparc-benchmark.pem${NC}"
    exit 1
fi
chmod 400 "$HOME/.ssh/cryosparc-benchmark.pem"

if ! aws ec2 describe-security-groups --group-ids ${SECURITY_GROUP} --region ${REGION} &>/dev/null; then
    echo -e "${RED}ERROR: Security group ${SECURITY_GROUP} not found${NC}"
    exit 1
fi
echo "✓ Prerequisites validated"

# Check spot price history
echo -e "${YELLOW}[2/7] Checking spot price history...${NC}"
CURRENT_SPOT_PRICE=$(aws ec2 describe-spot-price-history \
    --instance-types ${INSTANCE_TYPE} \
    --region ${REGION} \
    --start-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --product-descriptions "Linux/UNIX" \
    --query 'SpotPriceHistory[0].SpotPrice' \
    --output text)

echo "Current spot price: \$${CURRENT_SPOT_PRICE}/hour"
ESTIMATED_HOURS=$(echo "scale=1; 20 / ${CURRENT_SPOT_PRICE}" | bc)
echo "Max execution time with \$20 budget: ${ESTIMATED_HOURS} hours"

if (( $(echo "${CURRENT_SPOT_PRICE} > ${MAX_SPOT_PRICE}" | bc -l) )); then
    echo -e "${RED}WARNING: Spot price exceeds safety limit!${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create user data script
echo -e "${YELLOW}[3/7] Preparing instance configuration...${NC}"
cat > user_data.sh <<'EOF'
#!/bin/bash
set -ex

# Update system
apt-get update
apt-get install -y curl wget python3-pip jq bc docker.io

# Enable Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Install Nextflow
cd /opt
curl -s https://get.nextflow.io | bash
mv nextflow /usr/local/bin/
chmod +x /usr/local/bin/nextflow

# Install nvidia-docker for GPU support
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
    tee /etc/apt/sources.list.d/nvidia-docker.list
apt-get update
apt-get install -y nvidia-docker2
systemctl restart docker

# Install Python dependencies
pip3 install numpy biopython

# Create working directories
mkdir -p /home/ubuntu/biomate_runs
mkdir -p /home/ubuntu/alphafold_data
mkdir -p /home/ubuntu/alphafold_output
chown -R ubuntu:ubuntu /home/ubuntu/biomate_runs
chown -R ubuntu:ubuntu /home/ubuntu/alphafold_data
chown -R ubuntu:ubuntu /home/ubuntu/alphafold_output

# Create EBS mount point for AlphaFold databases (if needed)
mkdir -p /mnt/alphafold_db
chown ubuntu:ubuntu /mnt/alphafold_db

# Signal completion
touch /tmp/instance_ready
EOF

# Launch spot instance with larger disk
echo -e "${YELLOW}[4/7] Launching spot instance...${NC}"
INSTANCE_ID=$(aws ec2 run-instances \
    --region ${REGION} \
    --image-id ${AMI_ID} \
    --instance-type ${INSTANCE_TYPE} \
    --key-name ${KEY_NAME} \
    --security-group-ids ${SECURITY_GROUP} \
    --instance-market-options "MarketType=spot,SpotOptions={MaxPrice=${MAX_SPOT_PRICE},SpotInstanceType=one-time}" \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":500,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
    --user-data file://user_data.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${RUN_ID}},{Key=Project,Value=BioMate},{Key=Type,Value=AlphaFold3-Benchmark}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

if [ -z "${INSTANCE_ID}" ]; then
    echo -e "${RED}ERROR: Failed to launch instance${NC}"
    exit 1
fi

echo "✓ Instance launched: ${INSTANCE_ID}"
echo "${INSTANCE_ID}" > instance_id.txt

# Wait for instance to be running
echo -e "${YELLOW}[5/7] Waiting for instance to start...${NC}"
aws ec2 wait instance-running \
    --region ${REGION} \
    --instance-ids ${INSTANCE_ID}

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --region ${REGION} \
    --instance-ids ${INSTANCE_ID} \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo "✓ Instance running at ${PUBLIC_IP}"
echo "${PUBLIC_IP}" > public_ip.txt

# Wait for SSH to be available
echo -e "${YELLOW}[6/7] Waiting for SSH access...${NC}"
for i in {1..60}; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        -i "$HOME/.ssh/cryosparc-benchmark.pem" \
        ubuntu@${PUBLIC_IP} "echo connected" &>/dev/null; then
        break
    fi
    echo -n "."
    sleep 5
done
echo ""
echo "✓ SSH access ready"

# Wait for user data script to complete
echo -e "${YELLOW}[7/7] Waiting for instance initialization...${NC}"
ssh -o StrictHostKeyChecking=no \
    -i "$HOME/.ssh/cryosparc-benchmark.pem" \
    ubuntu@${PUBLIC_IP} \
    "while [ ! -f /tmp/instance_ready ]; do sleep 5; done"

echo "✓ Instance fully initialized"

# Save metadata
cat > metadata.json <<EOF
{
  "run_id": "${RUN_ID}",
  "instance_id": "${INSTANCE_ID}",
  "instance_type": "${INSTANCE_TYPE}",
  "public_ip": "${PUBLIC_IP}",
  "region": "${REGION}",
  "launch_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "spot_price": "${CURRENT_SPOT_PRICE}",
  "max_budget": "20.00",
  "estimated_max_hours": "${ESTIMATED_HOURS}",
  "purpose": "AlphaFold 3 benchmark"
}
EOF

# Print connection info
echo ""
echo -e "${GREEN}================================================"
echo "Instance Ready!"
echo "================================================${NC}"
echo "Instance ID: ${INSTANCE_ID}"
echo "Public IP: ${PUBLIC_IP}"
echo "SSH Command:"
echo "  ssh -i ~/.ssh/cryosparc-benchmark.pem ubuntu@${PUBLIC_IP}"
echo ""
echo "WARNING: This instance costs ~\$${CURRENT_SPOT_PRICE}/hour"
echo "Max runtime with \$20 budget: ${ESTIMATED_HOURS} hours"
echo ""
echo "Next steps:"
echo "  1. Setup AlphaFold 3: ./setup_instance.sh ${RUN_ID} alphafold"
echo "  2. Run benchmark: ./run_alphafold_benchmark.sh ${RUN_ID}"
echo "  3. Cleanup: ./terminate_instance.sh ${RUN_ID}"
echo ""
echo "Output directory: ${OUTPUT_DIR}"
echo "Metadata saved to: metadata.json"
echo -e "${GREEN}================================================${NC}"
