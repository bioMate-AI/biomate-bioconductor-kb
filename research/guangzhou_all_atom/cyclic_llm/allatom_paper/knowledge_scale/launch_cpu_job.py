"""Generic small CPU spot job for K2 post-processing (merge / measure / any shell command) on EC2, never the laptop.
usage: launch_cpu_job.py RUN_ID "SHELL COMMAND" [--s3-in S3URI=/w/in/name ...] [--code-extra PATH ...]
The command runs in /w/k2src (K2 code unpacked), outputs under /w/out (synced to s3://.../k2/<RUN_ID>/)."""
import argparse, io, os, subprocess, sys, tarfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
B = "s3://biomate-nextflow-work/cyclic_peptide/allatom/k2"
AMI, SG = "ami-0829b74b2a8c619b7", "sg-0de9af2d4437a8c90"
SUBNETS = ["subnet-0b35a6e2c1cf02dc2", "subnet-03b277a7a08d388c1", "subnet-09e4dce46682a6c60", "subnet-0254e4c3634b41bfc"]
TYPES = ["c6i.large", "c5.xlarge", "m6i.large", "c6a.large"]
UD = r'''#!/bin/bash
P=__P__
mkdir -p /w/out /w/k2src /w/in && cd /w
shutdown -h +60
exec > >(tee -a /w/out/boot.log) 2>&1
echo "boot $(date -u +%FT%TZ)"
( while true; do aws s3 sync /w/out $P/ --only-show-errors; sleep 20; done ) &
SYNC=$!
aws s3 cp __CODE__ /w/code.tgz --only-show-errors && tar xzf /w/code.tgz -C /w/k2src
__INPUTS__
dnf install -y python3.11 python3.11-pip >/w/out/dnf.log 2>&1
python3.11 -m pip install -q pytest >/w/out/pip.log 2>&1
cd /w/k2src
python3.11 -m pytest -q --import-mode=importlib -p no:cacheprovider test_k2.py > /w/out/tests.log 2>&1; echo "tests rc=$?" | tee -a /w/out/stage.log
__CMD__ > /w/out/job.log 2>&1; echo "job rc=$?" | tee -a /w/out/stage.log
echo DONE > /w/out/done.flag; aws s3 sync /w/out $P/ --only-show-errors
kill $SYNC; shutdown -h now
'''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_id")
    ap.add_argument("cmd")
    ap.add_argument("--s3-in", nargs="*", default=[], help="S3URI=/w/in/name")
    ap.add_argument("--code-extra", nargs="*", default=[], help="repo-relative-to-cwd file paths to ship as /w/k2src/<basename>")
    a = ap.parse_args()
    P = f"{B}/{a.run_id}"
    codekey = f"{P}_code/code.tgz"
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        for f in sorted(os.listdir(HERE)):
            if f.endswith(".py"):
                tf.add(os.path.join(HERE, f), arcname=f)
        for p in a.code_extra:
            tf.add(p, arcname=os.path.basename(p))
    tmp = f"/tmp/k2_cpu_{a.run_id}.tgz"
    open(tmp, "wb").write(buf.getvalue())
    subprocess.run(["aws", "s3", "cp", tmp, codekey, "--only-show-errors"], check=True)
    inputs = "\n".join(f"aws s3 cp {x.split('=')[0]} {x.split('=')[1]} --only-show-errors" for x in a.s3_in)
    ud = UD.replace("__P__", P).replace("__CODE__", codekey).replace("__INPUTS__", inputs).replace("__CMD__", a.cmd.replace("python ", "python3.11 "))
    udpath = f"/tmp/k2_cpu_ud_{a.run_id}.sh"
    open(udpath, "w").write(ud)
    last = ""
    for t in TYPES:
        for sub in SUBNETS:
            r = subprocess.run(["aws", "ec2", "run-instances", "--image-id", AMI, "--instance-type", t, "--subnet-id", sub, "--security-group-ids", SG,
                                "--iam-instance-profile", "Name=ecsInstanceRole",
                                "--instance-market-options", '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}',
                                "--instance-initiated-shutdown-behavior", "terminate",
                                "--block-device-mappings", '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":30,"VolumeType":"gp3"}}]',
                                "--user-data", f"file://{udpath}",
                                "--tag-specifications", "ResourceType=instance,Tags=[{Key=Name,Value=allatom-k2-cpu},{Key=project,Value=cyclic-selector}]",
                                "--query", "Instances[0].InstanceId", "--output", "text"], capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                iid = r.stdout.strip()
                open(os.path.join(HERE, "cost_log_k2.txt"), "a").write(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {a.run_id} {iid} {t} {sub}\n")
                print("LAUNCHED", iid, t, "prefix", P)
                return
            last = r.stderr[-200:]
    print("NO CAPACITY", last, file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
