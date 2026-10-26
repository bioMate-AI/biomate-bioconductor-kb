#!/bin/bash
# usage: submit_cofold.sh TAG "ID1,ID2,.." [N_SAMPLES] [OUT_SUBDIR]
# Submits ONE Batch job (SPOT queue only) running scripts/cofold_boltz_driver.py inside the Boltz image. Job def cycbench-cofold.
set -Eeuo pipefail
TAG=$1; IDS=$2; N=${3:-25}; SUB=${4:-boltz}
B=s3://biomate-nextflow-work/cyclic_peptide/cofold_bench
aws s3 cp "$(dirname "$0")/cofold_boltz_driver.py" $B/code/cofold_boltz_driver.py --only-show-errors
CMD='which aws >/dev/null 2>&1 || pip install -q awscli; export B=s3://biomate-nextflow-work/cyclic_peptide/cofold_bench; aws s3 cp $B/code/cofold_boltz_driver.py /tmp/d.py --only-show-errors; python /tmp/d.py 2>&1 | tee /tmp/job.log; RC=${PIPESTATUS[0]}; aws s3 cp /tmp/job.log $B/logs/$JOBTAG.log --only-show-errors; exit $RC'
OVR=$(python3 - "$CMD" "$IDS" "$N" "$SUB" "$TAG" <<'PY'
import json,sys
cmd,ids,n,sub,tag=sys.argv[1:]
B="s3://biomate-nextflow-work/cyclic_peptide/cofold_bench"
e=lambda **k:[{"name":a,"value":b} for a,b in k.items()]
print(json.dumps({"command":["bash","-c",cmd],"environment":e(IN_S3=B+"/inputs",OUT_S3=B+"/samples/"+sub,IDS=ids,N_SAMPLES=n,JOBTAG=tag)}))
PY
)
aws batch submit-job --region us-west-2 --job-name "cycbench-$TAG" --job-queue biomate-gpu-spot-queue --job-definition cycbench-cofold \
  --container-overrides "$OVR" --query jobId --output text
