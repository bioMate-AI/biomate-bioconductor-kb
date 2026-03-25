# CryoSPARC Real Execution Setup
*2026-03-12 07:00 UTC*

## Instance

| Property | Value |
|---|---|
| Instance ID | **TERMINATED 2026-03-12** (was i-04df9da48f8773183) |
| Type | g6.2xlarge (NVIDIA L4, 8 vCPU, 32GB RAM) |
| Region | us-east-1 |
| AMI (ready snapshot) | ami-008607f719aaac1b0 |
| Security group | sg-015137721b5fabddb (cryosparc-sg) |
| SSH key | cryosparc-benchmark / ~/.ssh/cryosparc-benchmark.pem |
| SSH user | ubuntu |
| **Cost when running** | ~$0.98/hr (g6.2xlarge on-demand) |
| **Cost when idle** | ~$0/hr — instance TERMINATED after each job; only AMI snapshot kept |
| **AMI snapshot cost** | ~$2/month (compressed, ~30-50 GB actual data) |

**No persistent instance. BioMate launches a fresh instance from AMI, runs the job, then TERMINATES it.**

## CryoSPARC v5 Config

| Property | Value |
|---|---|
| Port | 30000 (NOT 39000) |
| Hostname config | localhost (single-instance) |
| License | f312a30e-63fc-11f0-8e36-e3c932851287 |
| Project dir | /home/ubuntu/cryosparc_projects |
| Worker | localhost, lane=default, GPU 0 (NVIDIA L4) |
| Admin email | admin@biomate.ai |
| Admin password | BioMate2026! |

## Start CryoSPARC after instance start

```bash
export PATH=/home/ubuntu/cryosparc_master/bin:$PATH
cryosparcm start
```

The AMI (ami-008607f719aaac1b0) does NOT auto-start CryoSPARC — add to cron or user-data.
Worker reconnects automatically when master starts.

## BioMate Integration

**New files:**
- `backend/lib/galaxy/webapps/galaxy/api/cryosparc_executor.py`
  - `execute_spa_pipeline(run_id, params, user_id)` — async, threads
  - `ensure_cryosparc_running()` — auto-starts EC2 if stopped
  - `stop_instance()` — call after job completes to save cost
  - `get_run_status(run_id)` — returns dict compatible with nextflow status

**Config in `backend/.env`:**
```
CRYOSPARC_HOST=100.54.207.255
CRYOSPARC_PORT=30000
CRYOSPARC_EMAIL=admin@biomate.ai
CRYOSPARC_PASSWORD=BioMate2026!
CRYOSPARC_LICENSE=f312a30e-63fc-11f0-8e36-e3c932851287
CRYOSPARC_PROJECT_DIR=/home/ubuntu/cryosparc_projects
CRYOSPARC_INSTANCE_ID=i-04df9da48f8773183
CRYOSPARC_AMI_ID=ami-008607f719aaac1b0
CRYOSPARC_INSTANCE_REGION=us-east-1
CRYOSPARC_INSTANCE_TYPE=g6.2xlarge
CRYOSPARC_SSH_KEY=/home/yzhang/.ssh/cryosparc-benchmark.pem
CRYOSPARC_SSH_USER=ubuntu
```

## Pipeline steps (phase 1)

1. Start instance (if stopped) — ~3-5 min cold start
2. Connect via cryosparc-tools
3. Create project P-XXXX in /home/ubuntu/cryosparc_projects/
4. Create workspace W1
5. Import movies (blob_paths: movie_dir/*.eer)
6. Patch motion correction
7. Patch CTF estimation
8. (Future: particle picking, 2D/3D classification, refinement, FSC)

## On-demand deployment

To start for a job:
```bash
aws ec2 start-instances --region us-east-1 --instance-ids i-04df9da48f8773183
aws ec2 wait instance-running --region us-east-1 --instance-ids i-04df9da48f8773183
ssh -i ~/.ssh/cryosparc-benchmark.pem ubuntu@$(aws ec2 describe-instances \
  --region us-east-1 --instance-ids i-04df9da48f8773183 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text) \
  "export PATH=/home/ubuntu/cryosparc_master/bin:\$PATH && cryosparcm start"
```

BioMate's `cryosparc_executor.ensure_cryosparc_running()` does this automatically.

## Networking

- Port 30000 open in `cryosparc-sg` (all IPs)
- BioMate backend (us-west-2) connects to CryoSPARC API at `CRYOSPARC_HOST:30000`
- No VPN needed — public IP, port 30000 open

## Data

EMPIAR-10028 (β-galactosidase, 7028 EER movies) needs to be downloaded to the instance
before running the real pipeline. Download via:
```bash
# SSH to instance after starting
curl -O "https://ftp.ebi.ac.uk/empiar/world_availability/10028/data/micrographs/FoilHole_*.eer"
```
Or copy from S3 if pre-staged: `aws s3 sync s3://biomate-cryo-data/empiar-10028/ /home/ubuntu/empiar-10028/`
