"""Launch the K2 pilot on ONE g5/g6 spot instance (ecsInstanceRole). The laptop only uploads code and calls run-instances.
usage: launch_k2.py RUN_ID [--total 300] [--per-query 25]"""
import argparse, io, json, os, subprocess, sys, tarfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
B = "s3://biomate-nextflow-work/cyclic_peptide/allatom/k2"
AMI = "ami-04f7da1c787a89267"  # DL Base OSS Nvidia GPU AMI (CUDA drivers + awscli), used by launch_cyclic_llm_v2.sh
SG = "sg-0de9af2d4437a8c90"
# us-west-2d (subnet-0b35...) does not offer g5; use 2a/2b/2c
SUBNETS = ["subnet-0254e4c3634b41bfc", "subnet-03b277a7a08d388c1", "subnet-09e4dce46682a6c60"]
TYPES = ["g5.2xlarge", "g6e.xlarge", "g6e.2xlarge", "g6.2xlarge", "g5.4xlarge"]  # g5.2xlarge first (A10G, 32 GB RAM, ~USD 0.5/h); g6e = L40S 48 GB (bf16 8B + large KV cache); 24 GB GPUs only as fp8 fallback; >= 32 GB RAM needed to load the 15 GB checkpoint

UD = r'''#!/bin/bash
set -Eeuo pipefail
P=__P__
mkdir -p /w/out /w/k2src && cd /w
finish() {
  rc=$?
  trap - EXIT
  set +e
  if [ "$rc" -eq 0 ]; then
    printf '{"status":"success","exit_code":0}\n' > /w/out/terminal_status.json
    printf DONE > /w/out/done.flag
  else
    rm -f /w/out/done.flag
    printf '{"status":"failed","exit_code":%s}\n' "$rc" > /w/out/terminal_status.json
  fi
  aws s3 sync /w/out "$P/" --only-show-errors
  sync_rc=$?
  if [ "$sync_rc" -ne 0 ]; then
    if [ "$rc" -eq 0 ]; then rc=$sync_rc; fi
    rm -f /w/out/done.flag
    printf '{"status":"failed","exit_code":%s,"sync_failed":true}\n' "$rc" > /w/out/terminal_status.json
    aws s3 rm "$P/done.flag" --only-show-errors || true
    aws s3 sync /w/out "$P/" --only-show-errors || true
  fi
  if [ -n "${SYNC:-}" ]; then kill "$SYNC" 2>/dev/null; fi
  shutdown -h now
  exit "$rc"
}
trap finish EXIT
shutdown -h +180
exec > >(tee -a /w/out/boot.log) 2>&1
echo "boot $(date -u +%FT%TZ) $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
( while true; do aws s3 sync /w/out $P/ --only-show-errors || true; sleep 30; done ) &
SYNC=$!
aws s3 cp __CODE__ /w/code.tgz --only-show-errors
tar xzf /w/code.tgz -C /w/k2src
cd /w/k2src
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv | tee /w/out/gpu.txt
python3 -m pip install -q virtualenv >/w/out/pip00.log 2>&1; python3 -m virtualenv -q /w/venv >/w/out/venv.log 2>&1; echo "venv rc=$?" | tee -a /w/out/stage.log
[ -x /w/venv/bin/python ] || { echo "NO VENV" | tee -a /w/out/stage.log; sleep 60; aws s3 sync /w/out $P/ --only-show-errors; shutdown -h now; exit 4; }
. /w/venv/bin/activate
pip install -q --upgrade pip >/w/out/pip0.log 2>&1
pip install -q vllm pytest >/w/out/pip1.log 2>&1; echo "pip rc=$?" | tee -a /w/out/stage.log
python -c "import vllm,torch;print('vllm',vllm.__version__,'torch',torch.__version__,'cuda',torch.cuda.is_available())" 2>&1 | tail -2 | tee -a /w/out/stage.log
python -m pytest -q --import-mode=importlib -p no:cacheprovider test_k2.py > /w/out/tests.log 2>&1; echo "tests rc=$?" | tee -a /w/out/stage.log
if ! grep -q "passed" /w/out/tests.log || grep -q "failed" /w/out/tests.log; then echo "TESTS FAILED" | tee -a /w/out/stage.log; sleep 120; aws s3 sync /w/out $P/ --only-show-errors; shutdown -h now; exit 3; fi
__ACQUIRE__
__RESUME__python extract.py --corpus /w/out/corpus.jsonl.gz --outdir /w/out/extract > /w/out/extract.log 2>&1; echo "extract rc=$?" | tee -a /w/out/stage.log
python - <<'PY'
import gzip,json
idx=[{"pmcid":p["pmcid"],"doi":p.get("doi"),"tier":p["tier"],"year":p.get("year"),"n_words":p["n_words"],"text_sha256":p["text_sha256"],"query_id":p["query_id"]} for p in (json.loads(l) for l in gzip.open("/w/out/corpus.jsonl.gz","rt"))]
json.dump(idx,open("/w/out/corpus_index.json","w"))
PY
python kb_before.py /w/out/kb_before.json > /w/out/kb_before.log 2>&1; echo "kb_before rc=$?" | tee -a /w/out/stage.log
[ -s /w/out/kb_before.json ] || echo "[]" > /w/out/kb_before.json
python merge.py --rules /w/out/extract/rules_verified.jsonl --annotations /w/k2src/annotations.csv.gz --outdir /w/out/kb --before /w/out/kb_before.json > /w/out/merge.log 2>&1; echo "merge rc=$?" | tee -a /w/out/stage.log
GOLD=""; [ -f /w/k2src/gold.jsonl ] && GOLD="--gold /w/k2src/gold.jsonl"
python measure.py --rules /w/out/kb/knowledge_kb_scaled_v1.jsonl --corpus-index /w/out/corpus_index.json $GOLD --out /w/out/k2 > /w/out/measure.log 2>&1; echo "measure rc=$?" | tee -a /w/out/stage.log
exit 0
'''


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_id")
    ap.add_argument("--total", type=int, default=300)
    ap.add_argument("--per-query", type=int, default=25)
    ap.add_argument("--gold", help="optional K gold file to ship with the code as gold.jsonl")
    ap.add_argument("--resume-from", help="s3 URI of an earlier run's extract/ directory to continue from (done_passages.txt, rules, stats)")
    ap.add_argument("--reuse-corpus", help="s3 URI of a corpus.jsonl.gz from an earlier run: skips acquisition")
    a = ap.parse_args()
    P = f"{B}/{a.run_id}"
    codekey = f"{P}_code/code.tgz"
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        for f in sorted(os.listdir(HERE)):
            if f.endswith(".py") or f.endswith(".json"):
                tf.add(os.path.join(HERE, f), arcname=f)
        # kb_before imports experience_kb from the cyclic_llm dir: ship the minimal module tree
        cl = os.path.abspath(os.path.join(HERE, "..", ".."))
        for f in ("experience_kb.py", "medchem_kb.py", "pharmacophore_knowledge.py", "knowledge_liability_flags.py",
                  "kb_target_map.py"):
            p = os.path.join(cl, f)
            if os.path.exists(p):
                tf.add(p, arcname=f"cyclic_llm_mod/{f}")
        tdir = os.path.join(cl, "target_kb")
        if os.path.isdir(tdir):
            tf.add(tdir, arcname="cyclic_llm_mod/target_kb")
        ann = os.path.join(cl, "stratification", "data", "annotations.csv.gz")
        tf.add(ann, arcname="annotations.csv.gz")
        if a.gold:
            tf.add(a.gold, arcname="gold.jsonl")
    tmp = f"/tmp/k2_code_{a.run_id}.tgz"
    open(tmp, "wb").write(buf.getvalue())
    run(["aws", "s3", "cp", tmp, codekey, "--only-show-errors"])
    if a.reuse_corpus:
        acq = f'aws s3 cp {a.reuse_corpus} /w/out/corpus.jsonl.gz --only-show-errors > /w/out/acquire.log 2>&1; echo "acquire(reused) rc=$?" | tee -a /w/out/stage.log'
    else:
        acq = 'python acquire.py --out /w/out/corpus.jsonl.gz --per-query __PQ__ --total __TOTAL__ > /w/out/acquire.log 2>&1; echo "acquire rc=$?" | tee -a /w/out/stage.log'
    resume = (f"mkdir -p /w/out/extract && aws s3 sync {a.resume_from} /w/out/extract/ --only-show-errors; echo \"resumed from {a.resume_from}\" | tee -a /w/out/stage.log\n"
              if a.resume_from else "")
    ud = UD.replace("__RESUME__", resume).replace("__ACQUIRE__", acq).replace("__P__", P).replace("__CODE__", codekey).replace("__PQ__", str(a.per_query)).replace("__TOTAL__", str(a.total))
    udpath = f"/tmp/k2_ud_{a.run_id}.sh"
    for t in TYPES:
        qline = "" if t.startswith("g6e") else "export K2_QUANT=fp8   # 24 GB GPU fallback (recorded in extract_config.json)\n"
        open(udpath, "w").write(ud.replace("cd /w/k2src\n", "cd /w/k2src\n" + qline, 1))
        for sub in SUBNETS:
            r = subprocess.run(["aws", "ec2", "run-instances", "--image-id", AMI, "--instance-type", t, "--subnet-id", sub,
                                "--security-group-ids", SG, "--iam-instance-profile", "Name=ecsInstanceRole",
                                "--instance-market-options", '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}',
                                "--instance-initiated-shutdown-behavior", "terminate",
                                "--block-device-mappings", '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":120,"VolumeType":"gp3"}}]',
                                "--user-data", f"file://{udpath}",
                                "--tag-specifications", f"ResourceType=instance,Tags=[{{Key=Name,Value=allatom-k2}},{{Key=project,Value=cyclic-selector}}]",
                                "--query", "Instances[0].InstanceId", "--output", "text"], capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                iid = r.stdout.strip()
                row = f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {a.run_id} {iid} {t} {sub}\n"
                open(os.path.join(HERE, "cost_log_k2.txt"), "a").write(row)
                print("LAUNCHED", iid, t, sub, "prefix", P)
                return
    print("NO CAPACITY; last error:", (r.stderr or "")[-200:], file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
