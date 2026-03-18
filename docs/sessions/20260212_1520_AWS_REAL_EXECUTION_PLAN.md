# AWS Real Execution Plan - All Workflows
**Date**: 2026-02-12 15:20
**Purpose**: Test all 9 workflows on AWS with real execution (NO MOCK)
**Goal**: Document time and computational cost, compare with native tools

---

## ⚠️ CRITICAL: Spot Instance Policy

Per CLAUDE.md:
- **ALWAYS** use spot instances (NEVER on-demand)
- User **REFUSES** on-demand resources
- Exception: Only if NO spot in TWO different regions
- Cost savings: 67% ($0.50/hr vs $1.50/hr for g6.2xlarge)

---

## Execution Plan Overview

### Phase 1: AlphaFold 3 Real Execution
- **Instance Required**: g6.2xlarge or better (A100-80GB preferred)
- **Estimated Cost**: $0.50-3.00/hr (spot)
- **Estimated Time**: 10-30 min per protein
- **Comparison**: vs AlphaFold Server API (free, 20/day limit)

### Phase 2: CryoEM Standard SPA Real Execution
- **Instance Required**: g6.2xlarge (min 32GB RAM)
- **CryoSPARC License**: f312a30e-63fc-11f0-8e36-e3c932851287
- **Estimated Cost**: $0.50/hr (spot)
- **Estimated Time**: 2-4 hours for complete dataset
- **Comparison**: vs native CryoSPARC GUI workflow

### Phase 3: CryoEM Specialized Workflows
- **Instance**: Same as Phase 2
- **7 workflows** to test
- **Estimated Cost**: $0.50/hr × 7 workflows
- **Estimated Time**: 1-3 hours each

---

## Detailed Implementation

### Step 1: Launch Spot Instance

**Regions to Try** (in order):
1. us-east-1 (primary)
2. us-west-2 (secondary)

**Command for CryoEM** (g6.2xlarge):
```bash
aws ec2 request-spot-instances \
  --region us-east-1 \
  --instance-count 1 \
  --type "one-time" \
  --launch-specification '{
    "ImageId": "ami-0c7217cdde317cfec",
    "InstanceType": "g6.2xlarge",
    "KeyName": "cryosparc-benchmark",
    "SecurityGroupIds": ["sg-015137721b5fabddb"],
    "BlockDeviceMappings": [{
      "DeviceName": "/dev/sda1",
      "Ebs": {
        "VolumeSize": 500,
        "VolumeType": "gp3"
      }
    }]
  }' \
  --spot-price "0.50"
```

**Command for AlphaFold 3** (larger instance needed):
```bash
aws ec2 request-spot-instances \
  --region us-east-1 \
  --instance-count 1 \
  --type "one-time" \
  --launch-specification '{
    "ImageId": "ami-0c7217cdde317cfec",
    "InstanceType": "g5.12xlarge",
    "KeyName": "cryosparc-benchmark",
    "SecurityGroupIds": ["sg-015137721b5fabddb"],
    "BlockDeviceMappings": [{
      "DeviceName": "/dev/sda1",
      "Ebs": {
        "VolumeSize": 1000,
        "VolumeType": "gp3"
      }
    }]
  }' \
  --spot-price "2.50"
```

### Step 2: Setup Instance

**After spot instance launches**:
```bash
# Get instance IP
INSTANCE_IP=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# SSH into instance
ssh -i ~/.ssh/cryosparc-benchmark.pem ubuntu@$INSTANCE_IP

# Install dependencies
sudo apt-get update
sudo apt-get install -y docker.io nvidia-docker2 nextflow
```

**For CryoSPARC**:
```bash
# Install CryoSPARC (v5.0+)
curl -L https://get.cryosparc.com/download/master-latest/$LICENSE_ID > cryosparc_master.tar.gz
tar -xf cryosparc_master.tar.gz
cd cryosparc_master
./install.sh --license $LICENSE_ID --port 30000

# Install cryosparc-tools
pip install cryosparc-tools
```

**For AlphaFold 3**:
```bash
# Pull AlphaFold 3 container
docker pull ghcr.io/google-deepmind/alphafold3:latest

# Download databases (630 GB)
mkdir -p /data/alphafold3_db
cd /data/alphafold3_db
# Download script from AlphaFold repo
```

### Step 3: Upload Workflows and Data

**Copy workflows to instance**:
```bash
# From local machine
rsync -avz -e "ssh -i ~/.ssh/cryosparc-benchmark.pem" \
  backend/biomni_workflows/nextflow_nfcore/subworkflows/ \
  ubuntu@$INSTANCE_IP:~/workflows/
```

**Upload test data**:

**For CryoEM**:
```bash
# Download EMPIAR-10940 (T20S dataset, ~100GB)
# OR use smaller test dataset
wget https://ftp.ebi.ac.uk/empiar/world_availability/10940/data/Movies/*.tif
```

**For AlphaFold 3**:
```bash
# Use test sequences (already in workflow)
# No data download needed
```

### Step 4: Execute Workflows with Time and Cost Tracking

**Create tracking script**:
```bash
#!/bin/bash
# track_execution.sh

WORKFLOW_NAME=$1
START_TIME=$(date +%s)
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
SPOT_PRICE=$(aws ec2 describe-spot-price-history \
  --instance-types $INSTANCE_TYPE \
  --max-items 1 \
  --query 'SpotPriceHistory[0].SpotPrice' \
  --output text)

echo "=== Execution Tracking ==="
echo "Workflow: $WORKFLOW_NAME"
echo "Instance: $INSTANCE_TYPE"
echo "Spot Price: \$$SPOT_PRICE/hr"
echo "Start Time: $(date)"
echo "=========================="

# Run workflow
nextflow run $WORKFLOW_NAME -profile aws --outdir /data/results

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
HOURS=$(echo "scale=2; $DURATION / 3600" | bc)
COST=$(echo "scale=2; $HOURS * $SPOT_PRICE" | bc)

echo "=== Execution Complete ==="
echo "Duration: ${DURATION}s (${HOURS} hours)"
echo "Cost: \$$COST"
echo "=========================="

# Save to results
cat > /data/results/execution_metrics.json <<EOF
{
  "workflow": "$WORKFLOW_NAME",
  "instance_type": "$INSTANCE_TYPE",
  "spot_price_per_hour": $SPOT_PRICE,
  "start_time": $(date -d @$START_TIME +%s),
  "end_time": $(date -d @$END_TIME +%s),
  "duration_seconds": $DURATION,
  "duration_hours": $HOURS,
  "total_cost_usd": $COST
}
EOF
```

### Step 5: Execute Each Workflow

**AlphaFold 3**:
```bash
cd ~/workflows/structural_biology/alphafold3_complete_workflow
bash ~/track_execution.sh main.nf
```

**CryoEM Standard SPA**:
```bash
cd ~/workflows/cryo_em/cryosparc_standard_spa
bash ~/track_execution.sh main.nf
```

**CryoEM Specialized** (7 workflows):
```bash
cd ~/workflows/cryo_em/cryosparc_workflows
for workflow in helical membrane_protein high_resolution heterogeneity 3dflex topaz_picking local_refinement; do
  cd ${workflow}_workflow
  bash ~/track_execution.sh main.nf
  cd ..
done
```

### Step 6: Native Tool Comparison

**For AlphaFold 3**:

**Native Method 1: AlphaFold Server**
```bash
# Manual steps:
# 1. Go to https://alphafoldserver.com
# 2. Upload sequence
# 3. Submit job
# 4. Wait for result (typically 10-30 min)
# Time: 10-30 min
# Cost: FREE (20 jobs/day limit)
```

**Native Method 2: Local AlphaFold 3**
```bash
# Direct Docker execution
docker run --gpus all \
  -v /data/alphafold3_db:/data \
  -v /data/input:/input \
  -v /data/output:/output \
  ghcr.io/google-deepmind/alphafold3:latest \
  --input /input/input.json \
  --output /output
# Time: 10-30 min
# Cost: Same as workflow (same instance)
```

**For CryoEM - Native CryoSPARC GUI**:
```bash
# Manual steps via GUI:
# 1. Open CryoSPARC at http://instance-ip:30000
# 2. Create project manually
# 3. Import movies
# 4. Queue each job manually (23 jobs total)
# 5. Click "Run" for each job
# 6. Wait for each to complete before queuing next
# Time: 2-4 hours + manual overhead (~30-60 min)
# Cost: Same instance cost + researcher time
```

**For CryoEM - CryoSPARC CLI**:
```bash
# Direct cryosparc-tools API
python3 << 'EOF'
from cryosparc.tools import CryoSPARC
cs = CryoSPARC(license='...', host='localhost', base_port=30000)
project = cs.create_project('P1')
workspace = project.create_workspace('W1')
# ... queue 23 jobs manually in Python
# Time: 2-4 hours + scripting overhead (~15-30 min)
# Cost: Same instance cost
EOF
```

---

## Expected Results

### Time Comparison

| Workflow | BioMate Nextflow | Native Tool | Time Saved |
|----------|------------------|-------------|------------|
| AlphaFold 3 | 15 min (automated) | 20-30 min (manual) | 5-15 min |
| CryoEM Standard SPA | 2.5 hrs (automated) | 3-4 hrs (manual GUI) | 0.5-1.5 hrs |
| Helical | 1.5 hrs (automated) | 2-3 hrs (manual) | 0.5-1.5 hrs |
| Membrane Protein | 2 hrs (automated) | 2.5-3.5 hrs (manual) | 0.5-1.5 hrs |
| High Resolution | 3 hrs (automated) | 3.5-4.5 hrs (manual) | 0.5-1.5 hrs |
| Heterogeneity | 2 hrs (automated) | 2.5-3.5 hrs (manual) | 0.5-1.5 hrs |
| 3DFlex | 4 hrs (automated) | 5-6 hrs (manual) | 1-2 hrs |
| Topaz Picking | 1 hr (automated) | 1.5-2 hrs (manual) | 0.5-1 hr |
| Local Refinement | 1.5 hrs (automated) | 2-3 hrs (manual) | 0.5-1.5 hrs |

### Cost Comparison

| Instance Type | Spot Price/hr | On-Demand/hr | Savings |
|---------------|---------------|--------------|---------|
| g6.2xlarge (CryoEM) | $0.50 | $1.50 | 67% |
| g5.12xlarge (AF3) | $2.50 | $7.50 | 67% |

**Total Estimated Costs** (all 9 workflows):
- AlphaFold 3: $2.50 × 0.25 hrs = **$0.63**
- CryoEM Standard SPA: $0.50 × 2.5 hrs = **$1.25**
- 7 Specialized workflows: $0.50 × (1.5+2+3+2+4+1+1.5) = **$7.50**
- **TOTAL**: ~**$9.38** (all workflows, real execution)

**vs On-Demand**: ~$28.14 (user REFUSES this)

---

## Data Collection Template

For each workflow, collect:

```json
{
  "workflow_name": "alphafold3_complete_workflow",
  "execution_method": "biomate_nextflow",
  "instance_type": "g5.12xlarge",
  "spot_price_usd_per_hour": 2.50,
  "execution_metrics": {
    "start_time": "2026-02-12T15:30:00Z",
    "end_time": "2026-02-12T15:45:00Z",
    "duration_seconds": 900,
    "duration_minutes": 15,
    "total_cost_usd": 0.63
  },
  "resource_usage": {
    "peak_cpu_percent": 85,
    "peak_memory_gb": 64,
    "peak_gpu_percent": 95,
    "peak_gpu_memory_gb": 75,
    "disk_io_gb": 125
  },
  "output_quality": {
    "final_resolution_angstroms": 2.1,
    "confidence_metrics": {
      "ptm": 0.89,
      "iptm": 0.82,
      "plddt_mean": 87.3
    }
  },
  "comparison_native": {
    "method": "alphafold_server_api",
    "duration_minutes": 25,
    "cost_usd": 0.00,
    "time_difference_minutes": -10,
    "cost_difference_usd": 0.63,
    "notes": "Native is free but has 20/day limit"
  }
}
```

---

## Modified Workflow Configs for Real Execution

### Update nextflow.config for each workflow:

**cryosparc_standard_spa/nextflow.config**:
```groovy
profiles {
    aws {
        params.mock_mode = false
        params.cryosparc_license = 'f312a30e-63fc-11f0-8e36-e3c932851287'
        params.cryosparc_host = 'localhost'
        params.cryosparc_port = 30000
        params.movies_path = '/data/movies/*.tif'

        process {
            executor = 'local'
            cpus = 8
            memory = '32 GB'
            queue = 'GPU'
        }
    }
}
```

**alphafold3_complete_workflow/nextflow.config**:
```groovy
profiles {
    aws {
        params.mock_mode = false
        params.alphafold3_db_path = '/data/alphafold3_db'
        params.use_docker = true

        process {
            container = 'ghcr.io/google-deepmind/alphafold3:latest'
            executor = 'local'
            cpus = 16
            memory = '64 GB'
            containerOptions = '--gpus all'
        }
    }
}
```

---

## Execution Checklist

### Pre-Flight
- [ ] Confirm spot instance availability in us-east-1
- [ ] Confirm spot instance availability in us-west-2 (backup)
- [ ] Verify CryoSPARC license: f312a30e-63fc-11f0-8e36-e3c932851287
- [ ] Download test datasets (EMPIAR-10940 or smaller)
- [ ] Review cost estimates (~$10 total)

### Launch
- [ ] Request spot instance (g6.2xlarge for CryoEM, g5.12xlarge for AF3)
- [ ] Wait for fulfillment (typically <5 min)
- [ ] SSH into instance
- [ ] Install dependencies (Docker, Nextflow, CryoSPARC)
- [ ] Upload workflows and data

### Execute
- [ ] Test 1: AlphaFold 3 (15 min, $0.63)
- [ ] Test 2: CryoEM Standard SPA (2.5 hrs, $1.25)
- [ ] Test 3: Helical workflow (1.5 hrs, $0.75)
- [ ] Test 4: Membrane protein workflow (2 hrs, $1.00)
- [ ] Test 5: High resolution workflow (3 hrs, $1.50)
- [ ] Test 6: Heterogeneity workflow (2 hrs, $1.00)
- [ ] Test 7: 3DFlex workflow (4 hrs, $2.00)
- [ ] Test 8: Topaz picking workflow (1 hr, $0.50)
- [ ] Test 9: Local refinement workflow (1.5 hrs, $0.75)

### Compare
- [ ] Run AlphaFold 3 via native Docker (15 min, $0.63)
- [ ] Run CryoEM SPA via CryoSPARC GUI (3-4 hrs, $1.50-2.00)
- [ ] Document time differences
- [ ] Document cost differences
- [ ] Document usability differences

### Collect Results
- [ ] Download all execution metrics JSON files
- [ ] Download all output files for validation
- [ ] Create comparison report
- [ ] Generate cost analysis
- [ ] Terminate spot instance

---

## Safety and Cost Controls

1. **Set billing alerts**:
   ```bash
   aws budgets create-budget \
     --budget Name=BiomateWorkflowTest,BudgetLimit={Amount=20,Unit=USD}
   ```

2. **Auto-terminate after X hours**:
   ```bash
   # In instance
   sudo shutdown -h +8h  # Terminate after 8 hours max
   ```

3. **Monitor costs**:
   ```bash
   # Check current month costs
   aws ce get-cost-and-usage \
     --time-period Start=$(date -d "$(date +%Y-%m-01)" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
     --granularity MONTHLY \
     --metrics UnblendedCost
   ```

---

## Next Steps

Would you like me to:
1. **Create modified workflow configs** with real execution (no mock)?
2. **Generate AWS launch scripts** with spot instance automation?
3. **Build comparison test suite** to run native tools side-by-side?
4. **Create cost tracking dashboard** to monitor in real-time?

**Estimated Total Cost**: ~$10-15 for all 9 workflows with real execution
**Estimated Total Time**: ~20-25 hours of computation (can run overnight)
**All using SPOT INSTANCES** per your policy (67% cost savings)
