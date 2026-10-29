"""Launch ONE CPU spot job for K4 (ecsInstanceRole). The laptop only uploads code and calls run-instances.
usage: launch_cpu.py RUN_ID "<command run inside /w/code>" [--type c6i.large] [--disk 60] [--hours 2]"""
import argparse, io, os, subprocess, sys, tarfile, time
HERE = os.path.dirname(os.path.abspath(__file__))
B = "s3://biomate-nextflow-work/cyclic_peptide/allatom/k4"
AMI = "ami-0829b74b2a8c619b7"; SG = "sg-0de9af2d4437a8c90"
SUBNETS = ["subnet-0b35a6e2c1cf02dc2", "subnet-03b277a7a08d388c1", "subnet-09e4dce46682a6c60", "subnet-0254e4c3634b41bfc"]
UD = r'''#!/bin/bash
P=__P__
mkdir -p /w/out /w/code && cd /w
shutdown -h +__MIN__
exec > >(tee -a /w/out/boot.log) 2>&1
echo "boot $(date -u +%FT%TZ) $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
( while true; do aws s3 sync /w/out $P/ --only-show-errors; sleep 30; done ) &
SYNC=$!
dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/w/out/dnf.log 2>&1
aws s3 cp __CODE__ /w/code.tgz --only-show-errors && tar xzf /w/code.tgz -C /w/code
cd /w/code
python3.11 -m pip install -q numpy pandas pyarrow duckdb rdkit pytest requests fsspec aiohttp >/w/out/pip.log 2>&1; echo "pip rc=$?" | tee -a /w/out/stage.log
( __CMD__ ) > /w/out/job.log 2>&1; echo "job rc=$?" | tee -a /w/out/stage.log
echo DONE > /w/out/done.flag; sleep 5; aws s3 sync /w/out $P/ --only-show-errors
kill $SYNC; shutdown -h now
'''
def main():
    ap = argparse.ArgumentParser(); ap.add_argument("run_id"); ap.add_argument("cmd")
    ap.add_argument("--type", default="c6i.large"); ap.add_argument("--disk", type=int, default=60); ap.add_argument("--hours", type=float, default=2.0)
    a = ap.parse_args()
    P = f"{B}/{a.run_id}"; codekey = f"{P}_code/code.tgz"
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        for f in sorted(os.listdir(HERE)):
            if f.endswith((".py", ".json", ".txt")) and not f.startswith("cost_log"):
                tf.add(os.path.join(HERE, f), arcname=f)
    tmp = f"/tmp/k4_code_{a.run_id}.tgz"; open(tmp, "wb").write(buf.getvalue())
    subprocess.run(["aws", "s3", "cp", tmp, codekey, "--only-show-errors"], check=True)
    ud = UD.replace("__P__", P).replace("__CODE__", codekey).replace("__CMD__", a.cmd).replace("__MIN__", str(int(a.hours * 60)))
    udp = f"/tmp/k4_ud_{a.run_id}.sh"; open(udp, "w").write(ud)
    for sub in SUBNETS:
        r = subprocess.run(["aws", "ec2", "run-instances", "--image-id", AMI, "--instance-type", a.type, "--subnet-id", sub, "--security-group-ids", SG,
                            "--iam-instance-profile", "Name=ecsInstanceRole", "--instance-market-options",
                            '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}',
                            "--instance-initiated-shutdown-behavior", "terminate", "--block-device-mappings",
                            f'[{{"DeviceName":"/dev/xvda","Ebs":{{"VolumeSize":{a.disk},"VolumeType":"gp3"}}}}]', "--user-data", f"file://{udp}",
                            "--tag-specifications", "ResourceType=instance,Tags=[{Key=Name,Value=allatom-k4},{Key=project,Value=cyclic-selector}]",
                            "--query", "Instances[0].InstanceId", "--output", "text"], capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            iid = r.stdout.strip()
            open(os.path.join(HERE, "cost_log_k4.txt"), "a").write(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {a.run_id} {iid} {a.type} {sub}\n")
            print("LAUNCHED", iid, a.type, sub, "prefix", P); return
    print("NO CAPACITY:", (r.stderr or "")[-200:], file=sys.stderr); sys.exit(2)
if __name__ == "__main__":
    main()
