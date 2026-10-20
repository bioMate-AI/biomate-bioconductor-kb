#!/usr/bin/env python3
"""physics_batch.py — route score()'s physics tier through AWS Batch (first wiring step).

AUDIT-FIRST finding (2026-10-19): the Batch primitive already exists in us-west-2 —
queue `biomate-gpu-spot-queue` (ENABLED) + Boltz cofold job-def `boltz-snat2-direct`
(image biomate/ai-tools/boltz:latest, GPU=1) + `biomate-ambertools-gpu` / GROMACS
job-defs for the MM-GBSA side. The gap is WIRING: the closed loop's score(tier='full')
-> physics_dispatch.physics_for() only READS pre-computed physics result files; nothing
DISPATCHES a cofold/MM-GBSA job for a new candidate. Physics is launched out-of-band by
the standalone EC2 launcher launch_cofold_v2.sh, which bypasses Batch entirely.

This module is the dispatch seam. It reuses target_spec.build_cofold_input (so the input
is spec-derived — metal is just `cofactors`) and submits ONE cofold job to the EXISTING
Boltz GPU-spot job-def. SAFETY: dry_run=True by DEFAULT — it validates that the real queue
+ job-def exist and emits the exact submit payload, but DOES NOT submit and spends nothing.
A real submission (dry_run=False) is one spot GPU job and must be gated behind a review
note + explicit go-ahead (see docs/20261019_LOOP_BATCH_SYSTEM_LEVER.md).

Not an at-scale sweep. One candidate, one job, reviewed. Relative-within-target physics,
control-gated downstream in score(); ground truth = wet-lab assay.
"""
import os, sys, json, time

REGION = "us-west-2"
QUEUE = "biomate-gpu-spot-queue"          # ENABLED spot GPU queue (audited)
JOBDEF = "boltz-snat2-direct"             # existing Boltz cofold job-def (audited)
BUCKET = "biomate-nextflow-work"          # bucket the Boltz job-def's role can read/write
PREFIX = "cyclic_peptide/batch_cofold"

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import target_spec


def _boto(svc):
    import boto3
    return boto3.client(svc, region_name=REGION)


def _boltz_command(input_s3, conv_s3, out_s3):
    """Pull the spec-derived input + the json_to_boltz_yaml converter from S3, build the Boltz YAML
    (receptor chains + cofactor CCD ligands + cyclic peptide), predict, upload. Boltz flags match the
    proven launch_cofold_v2.sh driver (--use_msa_server --override --no_kernels)."""
    return ["bash", "-c",
            "set -ex; (which aws || pip install -q awscli); "
            f"aws s3 cp {input_s3} /tmp/cofold_input.json; "
            f"aws s3 cp {conv_s3} /tmp/conv.py; "
            "python /tmp/conv.py /tmp/cofold_input.json /tmp/in.yaml; head -4 /tmp/in.yaml; "
            "boltz predict /tmp/in.yaml --out_dir /tmp/out --use_msa_server --override --no_kernels; "
            "CIF=$(find /tmp/out -name '*_model_0.cif' | head -1); "
            "[ -z \"$CIF\" ] && CIF=$(find /tmp/out -name '*.cif' | head -1); echo \"CIF=$CIF\"; "
            f"aws s3 cp /tmp/out {out_s3} --recursive; "
            f"[ -n \"$CIF\" ] && aws s3 cp \"$CIF\" {out_s3}complex.cif; echo COFOLD_BATCH_DONE"]


def dispatch_cofold(target, candidates, run_id=None, dry_run=True):
    """Dispatch ONE spec-derived cofold physics job to the existing Boltz GPU-spot Batch job-def.
    dry_run=True (default): validate real queue+job-def exist, emit the submit payload, SPEND NOTHING.
    dry_run=False: actually submit one spot GPU job (gate behind a review note + go-ahead)."""
    spec = target_spec.load_spec(target)
    if not spec:
        return {"error": f"no spec for target {target}"}
    ci = target_spec.build_cofold_input(spec, candidates)
    if ci.get("error"):
        return {"cold_start": ci["error"], "note": "receptor structure not prepped — no physics job to dispatch"}
    run_id = run_id or f"{target}-{int(time.time())}"
    base = f"s3://{BUCKET}/{PREFIX}/{run_id}"
    input_s3 = f"{base}/cofold_input.json"
    conv_s3 = f"{base}/json_to_boltz_yaml.py"
    out_s3 = f"{base}/complexes/"
    payload = dict(
        jobName=f"cofold-{run_id}".replace("_", "-")[:120],
        jobQueue=QUEUE, jobDefinition=JOBDEF,
        containerOverrides=dict(command=_boltz_command(input_s3, conv_s3, out_s3)),
        tags={"pipeline": "cyclic-peptide", "stage": "cofold", "target": target},
    )
    # read-only validation against the REAL infra (no spend)
    validated = {}
    try:
        b = _boto("batch")
        qs = [q["jobQueueName"] for q in b.describe_job_queues(jobQueues=[QUEUE])["jobQueues"]]
        jds = b.describe_job_definitions(jobDefinitionName=JOBDEF, status="ACTIVE")["jobDefinitions"]
        validated = {"queue_exists": QUEUE in qs, "jobdef_active": bool(jds),
                     "jobdef_image": (jds[0]["containerProperties"]["image"] if jds else None),
                     "ligands_from_spec": ci["ligands"], "n_peptides": len(ci["peptides"])}
    except Exception as e:
        validated = {"validation_error": f"{type(e).__name__}: {str(e)[:150]}"}
    if dry_run:
        return {"dry_run": True, "would_upload": input_s3, "would_submit": payload,
                "validated": validated, "result_prefix": out_s3}
    # REAL submit — one spot GPU job. Caller must have a review note + go-ahead.
    s3 = _boto("s3")
    s3.put_object(Bucket=BUCKET, Key=f"{PREFIX}/{run_id}/cofold_input.json", Body=json.dumps(ci).encode())
    conv_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "json_to_boltz_yaml.py")
    s3.put_object(Bucket=BUCKET, Key=f"{PREFIX}/{run_id}/json_to_boltz_yaml.py", Body=open(conv_path, "rb").read())
    jid = _boto("batch").submit_job(**payload)["jobId"]
    return {"dry_run": False, "submitted_job_id": jid, "input_s3": input_s3, "conv_s3": conv_s3, "result_prefix": out_s3}


def fetch_result(run_id, target):
    """Poll S3 for the cofold complex(es) of a dispatched run (the retrieve half of the seam)."""
    import botocore
    key = f"{PREFIX}/{run_id}/complexes/"
    try:
        objs = _boto("s3").list_objects_v2(Bucket=BUCKET, Prefix=key).get("Contents", [])
        cifs = [o["Key"] for o in objs if o["Key"].endswith((".cif", ".mmcif"))]
        return {"ready": bool(cifs), "complexes": cifs}
    except Exception as e:
        return {"ready": False, "error": f"{type(e).__name__}: {str(e)[:120]}"}


if __name__ == "__main__":
    # ONE dispatch for avb6. dry_run unless --submit is passed (the gated single validation job).
    submit = "--submit" in sys.argv
    pep = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--pep=")), "FRGDLAFPK")  # avebehexin backbone
    rid = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--run-id=")), None)
    cands = [{"id": "VAL-001", "pep": pep}]
    out = dispatch_cofold("avb6", cands, run_id=rid, dry_run=not submit)
    print(json.dumps(out, indent=2, default=str))
