#!/bin/bash
# Give AWS Batch Nextflow hosts enough disk, and clean it up promptly.
#
# Why: Batch autoscaling adds INSTANCES; it never grows an instance's disk. Every host booted
# with the AMI's 30 GB root volume, shared by every container image it pulls (nf-core images are
# 1-3 GB; one pipeline uses dozens) and every task's scratch files. Batch bin-packs many tasks
# onto one r5.4xlarge, and the ECS agent kept stopped-task containers ~3 h by default — so
# concurrent nf-core runs died with "no space left on device" (rnaseq MultiQC, diaproteomics,
# slamseq, eager; 2026-11-06, docs/20261103_ALL_LLM_AGENTIC_UNIFICATION_AND_COLDSTART.md §16.6).
#
# What: creates a new version of the launch template from its CURRENT latest version with
#   - root volume ROOT_GB (default 200) gp3, encrypted, deleted on termination
#   - ECS agent cleanup: stopped-task containers removed after 15 min; unused images pruned
# Idempotent: exits without a new version when the latest already has both.
# Afterwards pin the CEs: scripts/audit_batch_ce_lt_versions.sh --apply (sync_to_dev.sh runs it).
#
# Usage: scripts/batch_lt_storage.sh [--apply]      (default: dry run, prints the change)
set -euo pipefail
REGION="${AWS_REGION:-us-west-2}"
LT_ID="${BATCH_LT_ID:-lt-099eb24c4fe1b477e}"
ROOT_GB="${ROOT_GB:-200}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

LATEST=$(aws ec2 describe-launch-templates --region "$REGION" --launch-template-ids "$LT_ID" \
  --query 'LaunchTemplates[0].LatestVersionNumber' --output text)
aws ec2 describe-launch-template-versions --region "$REGION" --launch-template-id "$LT_ID" \
  --versions "$LATEST" --query 'LaunchTemplateVersions[0].LaunchTemplateData' --output json > /tmp/lt_data.$$.json

rc=0
(python3 - "$ROOT_GB" /tmp/lt_data.$$.json /tmp/lt_new.$$.json <<'PY'
import base64, json, sys
root_gb, src, dst = int(sys.argv[1]), sys.argv[2], sys.argv[3]
d = json.load(open(src))
ECS_LINES = [
    "ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=15m",
    "ECS_IMAGE_CLEANUP_INTERVAL=10m",
    "ECS_IMAGE_MINIMUM_CLEANUP_AGE=20m",
    "ECS_NUM_IMAGES_DELETE_PER_CYCLE=10",
]
changed = []
bdm = d.get("BlockDeviceMappings") or []
root = next((b for b in bdm if b.get("DeviceName") == "/dev/xvda"), None)
if not root or (root.get("Ebs") or {}).get("VolumeSize", 0) < root_gb:
    bdm = [b for b in bdm if b.get("DeviceName") != "/dev/xvda"] + [{
        "DeviceName": "/dev/xvda",  # AL2023 ECS AMI root device
        "Ebs": {"VolumeSize": root_gb, "VolumeType": "gp3", "Encrypted": True, "DeleteOnTermination": True},
    }]
    d["BlockDeviceMappings"] = bdm
    changed.append(f"root volume -> {root_gb} GB gp3")
ud = base64.b64decode(d.get("UserData", "")).decode()
if "ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION" not in ud:
    marker = "#!/bin/bash\n"
    if marker not in ud:
        sys.exit("user data has no shell part to extend")
    block = ("# ECS agent cleanup: free disk from stopped tasks and unused images promptly\n"
             "mkdir -p /etc/ecs\n" + "".join(f"echo '{l}' >> /etc/ecs/ecs.config\n" for l in ECS_LINES))
    ud = ud.replace(marker, marker + block, 1)
    d["UserData"] = base64.b64encode(ud.encode()).decode()
    changed.append("ECS cleanup settings")
json.dump(d, open(dst, "w"))
print("CHANGES:", ", ".join(changed) if changed else "none")
sys.exit(0 if changed else 3)
PY
) || rc=$?
if [ "${rc:-0}" = 3 ]; then
  echo "[lt] $LT_ID v$LATEST already has the storage settings — nothing to do"; rm -f /tmp/lt_*.$$.json; exit 0
elif [ "${rc:-0}" != 0 ]; then
  echo "[lt] FAILED to build the new launch-template data (rc=$rc)"; rm -f /tmp/lt_*.$$.json; exit 1
fi
if [ $APPLY -eq 0 ]; then
  echo "[lt] dry run: would create a new version of $LT_ID from v$LATEST (pass --apply)"; rm -f /tmp/lt_*.$$.json; exit 0
fi
NEW=$(aws ec2 create-launch-template-version --region "$REGION" --launch-template-id "$LT_ID" \
  --source-version "$LATEST" --version-description "root ${ROOT_GB}GB gp3 + ECS cleanup (batch_lt_storage.sh)" \
  --launch-template-data "file:///tmp/lt_new.$$.json" --query 'LaunchTemplateVersion.VersionNumber' --output text)
rm -f /tmp/lt_*.$$.json
echo "[lt] created $LT_ID v$NEW (from v$LATEST). Pin CEs: scripts/audit_batch_ce_lt_versions.sh --apply"
