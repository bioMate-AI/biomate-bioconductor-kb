# vLLM Deploy Runbook — BioMate regulatory-LLM serving cluster

**Status:** Scaffolding committed. **Cost-optimized: 100% spot, desired=2 nodes, ~$165–$330/mo** (down from the original 80/20 5-node ~$1,760/mo plan). When all spot capacity is reclaimed, Galaxy backend falls back to the Gemini Flash path in `_call_local_regulatory_llm` — degraded latency + quality, not an outage.

This runbook turns `infra/vllm/*` into a running 5-node ASG behind an ALB at `https://vllm.biomate.ai`. The Galaxy backend hits this endpoint via `VLLM_BASE_URL` env (already wired in `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py`).

## Architecture (recap)

```
        Galaxy backend (multiple instances)
                  │  VLLM_BASE_URL=https://vllm.biomate.ai
                  ▼
            ALB ───── target group ─── 5x g6.xlarge ASG
                                      │ 80% spot / 20% on-demand
                                      │ each: vllm container + spot-monitor
                                      ▼
                          EFS /mnt/efs/biomate-adapters
                          (synced from s3://biomate-models/regulatory_llm/)
```

## One-time bootstrap (run from a workstation with admin AWS creds)

### 1. Build + push the BioMate vLLM image to ECR

```bash
AWS_REGION=us-west-2
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY=$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com

aws ecr create-repository --repository-name biomate-vllm --region $AWS_REGION || true
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $REGISTRY

cd infra/vllm
docker build -t biomate-vllm:latest .
docker tag biomate-vllm:latest $REGISTRY/biomate-vllm:latest
docker push $REGISTRY/biomate-vllm:latest
```

### 2. Create the EFS + first adapter sync

```bash
aws efs create-file-system \
  --creation-token biomate-vllm-adapters \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --tags Key=Name,Value=biomate-vllm-adapters \
  --region $AWS_REGION
# Note the FileSystemId — call it $EFS_ID. Add a mount target per AZ.

# Seed adapters: from any host with the EFS mounted,
EFS_MOUNT=/mnt/efs/biomate-adapters bash infra/vllm/sync-adapters.sh
```

### 3. IAM instance profile

Attach: `AmazonEC2ContainerRegistryReadOnly`, `CloudWatchAgentServerPolicy`, and inline:

```json
{ "Version": "2012-10-17", "Statement": [
  { "Effect": "Allow",
    "Action": ["elasticloadbalancing:DeregisterTargets"],
    "Resource": "arn:aws:elasticloadbalancing:*:*:targetgroup/biomate-vllm-tg/*" }
] }
```

### 4. ALB + target group + listener

```bash
aws elbv2 create-target-group \
  --name biomate-vllm-tg \
  --protocol HTTP --port 8000 --vpc-id $VPC_ID \
  --health-check-path /health \
  --health-check-interval-seconds 15 \
  --healthy-threshold-count 2 --unhealthy-threshold-count 3
# … create ALB, listener on 443 with ACM cert, forward to target group.
```

### 5. Launch template + ASG

```bash
# Render cloud-init.yaml — substitute $EFS_ID, $TG_ARN, $REGION,
# $ECR_IMAGE=$REGISTRY/biomate-vllm:latest, $ECR_REGISTRY=$REGISTRY.
envsubst < infra/vllm/cloud-init.yaml > /tmp/cloud-init.rendered.yaml
USERDATA=$(base64 -w0 /tmp/cloud-init.rendered.yaml)

# Patch UserData into the launch template JSON
jq --arg ud "$USERDATA" '.LaunchTemplateData.UserData = $ud' \
  infra/vllm/asg-launch-template.json > /tmp/lt.json

aws ec2 create-launch-template \
  --launch-template-name biomate-vllm-lt \
  --version-description v1 \
  --launch-template-data "$(jq .LaunchTemplateData /tmp/lt.json)" \
  --region $AWS_REGION

aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name biomate-vllm-asg \
  --target-group-arns $TG_ARN \
  --min-size 1 --max-size 4 --desired-capacity 2 \
  --vpc-zone-identifier "$SUBNET_A,$SUBNET_B,$SUBNET_C" \
  --health-check-type ELB --health-check-grace-period 600 \
  --mixed-instances-policy "$(jq ._mixed_instances_policy /tmp/lt.json)" \
  --region $AWS_REGION
```

### 6. Wire the Galaxy backend

Set on every Galaxy instance:
```bash
export VLLM_BASE_URL=https://vllm.biomate.ai
```

Code path `_call_vllm_regulatory_llm` in `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py` already activates when this env is set. Run `e2e/billing-smoke.e2e.ts` and `e2e/ind-pi-suite.e2e.ts` to verify.

## Ongoing operations

### Deploy a new adapter (per-org or new global version)

```bash
# 1. Train + push to S3 — produces s3://biomate-models/regulatory_llm/<name>/lora_adapter/
# 2. From any host with EFS mounted:
ASG_NAME=biomate-vllm-asg bash infra/vllm/sync-adapters.sh
# That triggers a rolling instance refresh; new adapter serves within ~5 min.
```

### Watch a Spot interruption

```bash
aws logs tail /aws/ec2/biomate-vllm --follow --filter 'spot-monitor'
# Expected on reclamation:
#   [spot-monitor] SPOT INSTANCE ACTION DETECTED
#   [spot-monitor] deregistering i-… from arn:aws:…
#   [spot-monitor] drain wait: vllm_running_requests=2
#   [spot-monitor] in-flight drained (running=0)
#   [spot-monitor] SIGTERM vLLM
```

### Cost guardrails (100% spot)

- `desired=2 min=1 max=4`. Steady-state spot price for g6.xlarge in us-west-2 is ~$0.20–0.40/hr; 2 nodes × 24h × 30d ≈ **$290–$580/mo** worst case.
- `max-size=4` caps spend at ~$1,160/mo even if the autoscaler scales to ceiling.
- CloudWatch alarm on `GroupDesiredCapacity > 3` for 30 min → page on-call.
- If the endpoint is idle (no requests for 1h), an EventBridge rule scales `desired=1`. Cold-spin back to 2 takes ~3 min when traffic returns.
- **Spot-only failure mode:** if `capacity-optimized` cannot place any instance (region-wide squeeze), the ASG sits at desired=2/inservice=0 and the ALB returns 503. The Galaxy backend's `_call_local_regulatory_llm` fallback chain catches the 503 and routes to Gemini Flash — quality dips ~12pp but the user sees a response, not an error.

## Files in this scaffolding

| File | Purpose |
|---|---|
| `infra/vllm/Dockerfile` | Wraps `vllm/vllm-openai` with AWS CLI for spot management |
| `infra/vllm/start-vllm.sh` | Globs `/mnt/efs/.../lora_adapter/` → builds `--lora-modules` |
| `infra/vllm/spot-monitor.sh` | IMDSv2 polling + ALB deregister + drain + SIGTERM |
| `infra/vllm/cloud-init.yaml` | systemd units for EFS mount + biomate-vllm.service |
| `infra/vllm/asg-launch-template.json` | Launch template + Mixed Instances Policy |
| `infra/vllm/sync-adapters.sh` | S3 → EFS adapter sync + ASG refresh trigger |

## Out of scope (deliberate)

- **Terraform / CDK**: this runbook is `aws` CLI only. When the deploy stabilizes, convert to whichever IaC the team already uses elsewhere.
- **Auth on the ALB**: `vllm.biomate.ai` is private-subnet only; lock to Galaxy SG via security group, do not put it on the public internet.
- **Multi-region**: single us-west-2 deploy. Failover to a second region is a future workstream.
