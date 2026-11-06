"""Launch the K2 resource-import job on ONE small CPU spot instance (ecsInstanceRole). usage: launch_import.py RUN_ID"""
import io, os, subprocess, sys, tarfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
B = "s3://biomate-nextflow-work/cyclic_peptide/allatom/k2"
AMI, SG = "ami-0829b74b2a8c619b7", "sg-0de9af2d4437a8c90"
SUBNETS = ["subnet-0b35a6e2c1cf02dc2", "subnet-03b277a7a08d388c1", "subnet-09e4dce46682a6c60", "subnet-0254e4c3634b41bfc"]
TYPES = ["c6i.large", "c5.xlarge", "m6i.large", "c6a.large"]
UD = r'''#!/bin/bash
P=__P__
mkdir -p /w/out /w/code && cd /w
shutdown -h +90
exec > >(tee -a /w/out/boot.log) 2>&1
echo "boot $(date -u +%FT%TZ)"
( while true; do aws s3 sync /w/out $P/ --only-show-errors; sleep 30; done ) &
SYNC=$!
aws s3 cp __CODE__ /w/code.tgz --only-show-errors && tar xzf /w/code.tgz -C /w/code
cd /w/code
dnf install -y python3.11 python3.11-pip >/w/out/dnf.log 2>&1
python3.11 -m pip install -q rdkit openpyxl >/w/out/pip.log 2>&1; echo "pip rc=$?" | tee -a /w/out/stage.log
python3.11 import_resources.py --outdir /w/out/imports --local-cycpeptmpdb /w/code/annotations.csv.gz > /w/out/import.log 2>&1; echo "import rc=$?" | tee -a /w/out/stage.log
echo DONE > /w/out/done.flag; aws s3 sync /w/out $P/ --only-show-errors
kill $SYNC; shutdown -h now
'''


def main():
    run_id = sys.argv[1]
    P = f"{B}/{run_id}"
    codekey = f"{P}_code/code.tgz"
    buf = io.BytesIO()
    cl = os.path.abspath(os.path.join(HERE, "..", ".."))
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        tf.add(os.path.join(HERE, "import_resources.py"), arcname="import_resources.py")
        tf.add(os.path.join(cl, "stratification", "data", "annotations.csv.gz"), arcname="annotations.csv.gz")
    tmp = f"/tmp/k2_imp_{run_id}.tgz"
    open(tmp, "wb").write(buf.getvalue())
    subprocess.run(["aws", "s3", "cp", tmp, codekey, "--only-show-errors"], check=True)
    udpath = f"/tmp/k2_imp_ud_{run_id}.sh"
    open(udpath, "w").write(UD.replace("__P__", P).replace("__CODE__", codekey))
    last = ""
    for t in TYPES:
        for sub in SUBNETS:
            r = subprocess.run(["aws", "ec2", "run-instances", "--image-id", AMI, "--instance-type", t, "--subnet-id", sub,
                                "--security-group-ids", SG, "--iam-instance-profile", "Name=ecsInstanceRole",
                                "--instance-market-options", '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}',
                                "--instance-initiated-shutdown-behavior", "terminate",
                                "--block-device-mappings", '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":40,"VolumeType":"gp3"}}]',
                                "--user-data", f"file://{udpath}",
                                "--tag-specifications", "ResourceType=instance,Tags=[{Key=Name,Value=allatom-k2-import},{Key=project,Value=cyclic-selector}]",
                                "--query", "Instances[0].InstanceId", "--output", "text"], capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                iid = r.stdout.strip()
                open(os.path.join(HERE, "cost_log_k2.txt"), "a").write(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {run_id} {iid} {t} {sub}\n")
                print("LAUNCHED", iid, t, sub, "prefix", P)
                return
            last = r.stderr[-200:]
    print("NO CAPACITY", last, file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
