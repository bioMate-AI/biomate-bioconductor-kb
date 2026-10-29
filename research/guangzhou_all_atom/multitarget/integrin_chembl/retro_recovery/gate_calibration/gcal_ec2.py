"""Launch ONE throwaway spot job for the gate calibration (no compute on the laptop). Ships retro_recovery (data, cache, results) as a tarball to a per-run S3 prefix
(ONE writer), starts a spot instance (ecsInstanceRole), runs --cmd from the gate_calibration directory, uploads /w/out, boot log and a DONE flag, shuts down.
usage: gcal_ec2.py --name N --cmd 'shell' [--itype c5.9xlarge] [--cap-min 90]"""
import argparse, os, subprocess, tarfile, tempfile, time
BUCKET = "biomate-nextflow-work"; ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), *([".."] * 5)))
RR = "research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery"
AMI, SG = "ami-0829b74b2a8c619b7", "sg-0de9af2d4437a8c90"
SUBNETS = ["subnet-0b35a6e2c1cf02dc2", "subnet-03b277a7a08d388c1", "subnet-09e4dce46682a6c60", "subnet-0254e4c3634b41bfc"]
def sh(c): return subprocess.run(c, shell=True, capture_output=True, text=True)
def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--name", required=True); ap.add_argument("--cmd", required=True); ap.add_argument("--itype", default="c5.9xlarge"); ap.add_argument("--cap-min", type=int, default=90)
    ap.add_argument("--pip", default="numpy scipy pandas scikit-learn pytest rdkit"); a = ap.parse_args()
    rid = f"{a.name}-{int(time.time())}"; prefix = f"s3://{BUCKET}/cyclic_peptide/gate_calib/{rid}"; tgz = os.path.join(tempfile.gettempdir(), rid + ".tgz")
    with tarfile.open(tgz, "w:gz") as tf:
        tf.add(os.path.join(ROOT, RR), arcname=RR, filter=lambda ti: None if ("__pycache__" in ti.name or ti.name.endswith(".pyc") or ti.size > 150_000_000) else ti)
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
cd /w/{RR}/gate_calibration
export GPC_TOL=1e-6 GPC_TOL_C3=1e-3
( {a.cmd} ) > /w/out/run.log 2>&1; echo "rc=$?" >> /w/out/run.log
cp -r /w/{RR}/gate_calibration/results /w/out/ 2>/dev/null
aws s3 cp /w/out $P/out --recursive --only-show-errors
aws s3 cp /var/log/job.log $P/boot.log --only-show-errors
echo DONE > /w/DONE; aws s3 cp /w/DONE $P/DONE --only-show-errors
kill $SYNC; shutdown -h now
"""
    udf = os.path.join(tempfile.gettempdir(), rid + ".sh"); open(udf, "w").write(ud); iid = None
    for sub in SUBNETS:
        cmd = (f"aws ec2 run-instances --image-id {AMI} --instance-type {a.itype} --subnet-id {sub} --security-group-ids {SG} --iam-instance-profile Name=ecsInstanceRole "
               f"--instance-market-options '{{\"MarketType\":\"spot\",\"SpotOptions\":{{\"SpotInstanceType\":\"one-time\",\"InstanceInterruptionBehavior\":\"terminate\"}}}}' "
               f"--instance-initiated-shutdown-behavior terminate --block-device-mappings '[{{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{{\"VolumeSize\":60,\"VolumeType\":\"gp3\"}}}}]' --user-data file://{udf} "
               f"--tag-specifications 'ResourceType=instance,Tags=[{{Key=Name,Value=gate-calib-{a.name}}},{{Key=project,Value=cyclic-selector}}]' --query 'Instances[0].InstanceId' --output text")
        r = sh(cmd)
        if r.returncode == 0 and r.stdout.strip().startswith("i-"): iid = r.stdout.strip(); break
    print("PREFIX", prefix); print("INSTANCE", iid, a.itype); assert iid, "no capacity"
if __name__ == "__main__": main()
