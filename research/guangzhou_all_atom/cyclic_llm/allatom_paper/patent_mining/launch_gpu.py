"""Launch the K4 extraction on ONE g5/g6 spot GPU (ecsInstanceRole). usage: launch_gpu.py RUN_ID CORPUS_S3_URI [--max-patents N]"""
import argparse, io, os, subprocess, sys, tarfile, time
HERE = os.path.dirname(os.path.abspath(__file__))
B = "s3://biomate-nextflow-work/cyclic_peptide/allatom/k4"
AMI = "ami-04f7da1c787a89267"; SG = "sg-0de9af2d4437a8c90"
SUBNETS = ["subnet-0254e4c3634b41bfc", "subnet-03b277a7a08d388c1", "subnet-09e4dce46682a6c60"]
TYPES = ["g6.2xlarge", "g5.2xlarge", "g6.xlarge", "g5.xlarge", "g6e.xlarge", "g6e.2xlarge", "g5.4xlarge", "g6.4xlarge"]
UD = r'''#!/bin/bash
P=__P__
mkdir -p /w/out /w/code && cd /w
shutdown -h +180
exec > >(tee -a /w/out/boot.log) 2>&1
echo "boot $(date -u +%FT%TZ) $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
( while true; do aws s3 sync /w/out $P/ --only-show-errors; sleep 30; done ) &
SYNC=$!
aws s3 cp __CODE__ /w/code.tgz --only-show-errors && tar xzf /w/code.tgz -C /w/code
aws s3 cp __CORPUS__ /w/corpus.jsonl.gz --only-show-errors
cd /w/code
nvidia-smi --query-gpu=name,memory.total --format=csv | tee /w/out/gpu.txt
python3 -m pip install -q virtualenv >/w/out/pip00.log 2>&1; python3 -m virtualenv -q /w/venv >/w/out/venv.log 2>&1
[ -x /w/venv/bin/python ] || { echo "NO VENV" | tee -a /w/out/stage.log; sleep 60; aws s3 sync /w/out $P/ --only-show-errors; shutdown -h now; exit 4; }
. /w/venv/bin/activate
pip install -q --upgrade pip >/w/out/pip0.log 2>&1
pip install -q vllm pytest rdkit pandas >/w/out/pip1.log 2>&1; echo "pip rc=$?" | tee -a /w/out/stage.log
python -m pytest -q test_k4.py > /w/out/tests.log 2>&1; echo "tests rc=$?" | tee -a /w/out/stage.log
grep -q failed /w/out/tests.log && { echo "TESTS FAILED" | tee -a /w/out/stage.log; sleep 90; aws s3 sync /w/out $P/ --only-show-errors; shutdown -h now; exit 5; }
curl -s -L --retry 3 -o /w/bd.zip "https://www.bindingdb.org/rwd/bind/downloads/BindingDB_Patents_202610_tsv.zip"
T0=$(date +%s)
python extract_patents.py --corpus /w/corpus.jsonl.gz --outdir /w/out/extract __MAXP__ > /w/out/extract.log 2>&1; echo "extract rc=$?" | tee -a /w/out/stage.log
T1=$(date +%s)
HRS=$(python -c "print(round(($T1-$T0)/3600,3))")
python postprocess.py --extract /w/out/extract --corpus /w/corpus.jsonl.gz --out /w/out/pilot --bindingdb /w/bd.zip --cmpdb /w/code/annotations.csv.gz --cost-hours $HRS --cost-rate 0.0 > /w/out/postprocess.log 2>&1; echo "post rc=$?" | tee -a /w/out/stage.log
echo DONE > /w/out/done.flag; aws s3 sync /w/out $P/ --only-show-errors
kill $SYNC; shutdown -h now
'''
def main():
    ap = argparse.ArgumentParser(); ap.add_argument("run_id"); ap.add_argument("corpus"); ap.add_argument("--max-patents", type=int, default=0)
    a = ap.parse_args()
    P = f"{B}/{a.run_id}"; codekey = f"{P}_code/code.tgz"
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        for f in sorted(os.listdir(HERE)):
            if f.endswith((".py", ".json", ".txt")) and not f.startswith("cost_log"):
                tf.add(os.path.join(HERE, f), arcname=f)
        ann = os.path.abspath(os.path.join(HERE, "..", "..", "stratification", "data", "annotations.csv.gz"))
        if os.path.exists(ann):
            tf.add(ann, arcname="annotations.csv.gz")
    tmp = f"/tmp/k4g_code_{a.run_id}.tgz"; open(tmp, "wb").write(buf.getvalue())
    subprocess.run(["aws", "s3", "cp", tmp, codekey, "--only-show-errors"], check=True)
    ud = UD.replace("__P__", P).replace("__CODE__", codekey).replace("__CORPUS__", a.corpus).replace("__MAXP__", f"--max-patents {a.max_patents}" if a.max_patents else "")
    udp = f"/tmp/k4g_ud_{a.run_id}.sh"; open(udp, "w").write(ud)
    for t in TYPES:
        for sub in SUBNETS:
            r = subprocess.run(["aws", "ec2", "run-instances", "--image-id", AMI, "--instance-type", t, "--subnet-id", sub, "--security-group-ids", SG,
                                "--iam-instance-profile", "Name=ecsInstanceRole", "--instance-market-options",
                                '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}',
                                "--instance-initiated-shutdown-behavior", "terminate", "--block-device-mappings",
                                '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":120,"VolumeType":"gp3"}}]', "--user-data", f"file://{udp}",
                                "--tag-specifications", "ResourceType=instance,Tags=[{Key=Name,Value=allatom-k4},{Key=project,Value=cyclic-selector}]",
                                "--query", "Instances[0].InstanceId", "--output", "text"], capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                iid = r.stdout.strip()
                open(os.path.join(HERE, "cost_log_k4.txt"), "a").write(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {a.run_id} {iid} {t} {sub}\n")
                print("LAUNCHED", iid, t, sub, "prefix", P); return
    print("NO CAPACITY:", (r.stderr or "")[-200:], file=sys.stderr); sys.exit(2)
if __name__ == "__main__":
    main()
