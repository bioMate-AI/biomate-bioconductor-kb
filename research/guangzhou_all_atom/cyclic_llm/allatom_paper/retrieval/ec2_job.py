"""Launch ONE throwaway spot job (owner rule: no compute on the laptop). Packs the listed paths into a tarball on S3, starts a spot
instance (ecsInstanceRole, SG, tags project=cyclic-selector), runs the given shell commands, uploads /w/out and the boot log, shuts down.
Per-run S3 prefix, ONE writer: the launcher writes code.tgz BEFORE launch; the instance writes boot.log / out/ / DONE.
usage: ec2_job.py --name NAME --paths P1,P2 --cmd 'shell' [--pip 'pkgs'] [--cap-min 60] [--itype c6i.large]"""
import argparse, json, os, subprocess, sys, tarfile, tempfile, time

BUCKET = "biomate-nextflow-work"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", ".."))  # repo root
AMI, SG = "ami-0829b74b2a8c619b7", "sg-0de9af2d4437a8c90"
SUBNETS = ["subnet-0b35a6e2c1cf02dc2", "subnet-03b277a7a08d388c1", "subnet-09e4dce46682a6c60", "subnet-0254e4c3634b41bfc"]
TYPES = ["c6i.large", "c5.xlarge", "m6i.large", "c6i.xlarge"]


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True); ap.add_argument("--paths", required=True); ap.add_argument("--cmd", required=True)
    ap.add_argument("--pip", default="numpy scipy pandas scikit-learn pytest rdkit"); ap.add_argument("--cap-min", type=int, default=60)
    ap.add_argument("--itype", default=None); ap.add_argument("--disk", type=int, default=40)
    a = ap.parse_args()
    rid = f"{a.name}-{int(time.time())}"
    prefix = f"s3://{BUCKET}/cyclic_peptide/allatom/ib/{rid}"
    tgz = os.path.join(tempfile.gettempdir(), rid + ".tgz")
    with tarfile.open(tgz, "w:gz") as tf:
        for p in a.paths.split(","):
            tf.add(os.path.join(ROOT, p), arcname=p, filter=lambda ti: None if ("__pycache__" in ti.name or ti.name.endswith(".pyc") or "/results" in ti.name or ti.size > 8_000_000) else ti)
    r = sh(f"aws s3 cp {tgz} {prefix}/code.tgz --only-show-errors"); assert r.returncode == 0, r.stderr
    ud = f"""#!/bin/bash
P={prefix}
shutdown -h +{a.cap_min}
exec > /var/log/job.log 2>&1
( while true; do aws s3 cp /var/log/job.log $P/boot.log --only-show-errors; sleep 20; done ) &
SYNC=$!
dnf install -y python3.11 python3.11-pip tar >/dev/null 2>&1
python3.11 -m pip install -q {a.pip}
mkdir -p /w/out && cd /w && aws s3 cp $P/code.tgz . --only-show-errors && tar xzf code.tgz
export PYTHONPATH=/w/research/guangzhou_all_atom/cyclic_llm:/w/research/guangzhou_all_atom/cyclic_llm/allatom_paper
cd /w/research/guangzhou_all_atom/cyclic_llm
( {a.cmd} ) > /w/out/run.log 2>&1; echo "rc=$?" >> /w/out/run.log
aws s3 cp /w/out $P/out --recursive --only-show-errors
aws s3 cp /var/log/job.log $P/boot.log --only-show-errors
echo DONE > /w/DONE; aws s3 cp /w/DONE $P/DONE --only-show-errors
kill $SYNC; shutdown -h now
"""
    udf = os.path.join(tempfile.gettempdir(), rid + ".sh"); open(udf, "w").write(ud)
    iid = None
    for t in ([a.itype] if a.itype else TYPES):
        for sub in SUBNETS:
            cmd = (f"aws ec2 run-instances --image-id {AMI} --instance-type {t} --subnet-id {sub} --security-group-ids {SG} "
                   f"--iam-instance-profile Name=ecsInstanceRole --instance-market-options "
                   f"'{{\"MarketType\":\"spot\",\"SpotOptions\":{{\"SpotInstanceType\":\"one-time\",\"InstanceInterruptionBehavior\":\"terminate\"}}}}' "
                   f"--instance-initiated-shutdown-behavior terminate --block-device-mappings "
                   f"'[{{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{{\"VolumeSize\":{a.disk},\"VolumeType\":\"gp3\"}}}}]' --user-data file://{udf} "
                   f"--tag-specifications 'ResourceType=instance,Tags=[{{Key=Name,Value=allatom-ib-{a.name}}},{{Key=project,Value=cyclic-selector}}]' "
                   f"--query 'Instances[0].InstanceId' --output text")
            r = sh(cmd)
            if r.returncode == 0 and r.stdout.strip().startswith("i-"):
                iid = r.stdout.strip(); break
        if iid:
            break
    rec = dict(run_id=rid, prefix=prefix, instance=iid, itype=t if iid else None, launched=time.strftime("%FT%T%z"), cap_min=a.cap_min)
    print(json.dumps(rec))
    if iid:
        with open(os.path.join(os.path.dirname(__file__), "ib_cost_log.jsonl"), "a") as fh:
            fh.write(json.dumps(rec) + "\n")
    sys.exit(0 if iid else 2)


if __name__ == "__main__":
    main()
