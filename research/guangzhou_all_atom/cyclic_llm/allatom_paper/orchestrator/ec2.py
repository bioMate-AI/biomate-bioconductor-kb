"""EC2 spot helpers for the all-atom workstreams (owner rule: no compute on the laptop). Control-plane calls only (aws CLI):
upload code to S3, build the standard user-data, launch a spot instance, append a cost-log row.
Standard (docs/20261031_ALLATOM_IMPLEMENTATION_PLAN.md section 0): ecsInstanceRole (NOT AutoimmuneCorpusProfile), SG
sg-0de9af2d4437a8c90, root gp3 on /dev/xvda, tags project=cyclic-selector + Name, terminate-on-shutdown, wall-clock
`shutdown -h +N`, boot log to S3 every 20 s, NO bare `wait`, one writer per S3 prefix, self-terminating."""
from __future__ import annotations

import csv
import os
import subprocess
import sys
import time
from typing import List, Optional

AMI = "ami-0829b74b2a8c619b7"
SG = "sg-0de9af2d4437a8c90"
ROLE = "ecsInstanceRole"
SUBNETS = ["subnet-0b35a6e2c1cf02dc2", "subnet-03b277a7a08d388c1", "subnet-09e4dce46682a6c60", "subnet-0254e4c3634b41bfc"]
BUCKET = "s3://biomate-nextflow-work/cyclic_peptide/allatom"
HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)
COST_LOG = os.path.join(HERE, "cost_log_ia.csv")


def run_prefix(workstream: str, run_id: str) -> str:
    return f"{BUCKET}/{workstream}/{run_id}"


def make_userdata(prefix: str, command: str, wall_minutes: int = 60, pip: str = "numpy scipy pytest rdkit pandas scikit-learn") -> str:
    if "wait" in command.split():
        raise ValueError("bare `wait` is forbidden in launch scripts")
    return f"""#!/bin/bash
P={prefix}
shutdown -h +{int(wall_minutes)}
exec > /var/log/boot.log 2>&1
( while true; do aws s3 cp /var/log/boot.log $P/boot.log --only-show-errors; sleep 20; done ) &
SYNC=$!
dnf install -y python3.11 python3.11-pip >/dev/null 2>&1
python3.11 -m pip install -q {pip}
mkdir -p /w/out && cd /w
aws s3 cp $P/code/ . --recursive --only-show-errors
{command} > /w/cmd.log 2>&1
echo "cmd rc=$?" >> /w/cmd.log
aws s3 cp /w/cmd.log $P/cmd.log --only-show-errors
aws s3 cp /w/out $P/out --recursive --only-show-errors
kill $SYNC
aws s3 cp /var/log/boot.log $P/boot.log --only-show-errors
echo done > /w/done.flag
aws s3 cp /w/done.flag $P/done.flag --only-show-errors
shutdown -h now
"""


def upload_code(prefix: str) -> None:
    """Sync the allatom_paper package (flat layout under /w on the instance) to <prefix>/code/."""
    subprocess.run(["aws", "s3", "sync", PKG, prefix + "/code", "--exclude", "__pycache__/*", "--exclude", "*.pyc", "--exclude", ".pytest_cache/*",
                    "--exclude", "*.csv", "--only-show-errors", "--delete"], check=True)


def launch(userdata_path: str, name: str, itype: str = "c6i.large", root_gb: int = 40, subnets: Optional[List[str]] = None) -> str:
    """Launch ONE spot instance (spot only, never on-demand); returns the instance id or raises. Appends a cost-log row."""
    last = ""
    for sub in (subnets or SUBNETS):
        cmd = ["aws", "ec2", "run-instances", "--image-id", AMI, "--instance-type", itype, "--subnet-id", sub, "--security-group-ids", SG,
               "--iam-instance-profile", f"Name={ROLE}", "--instance-market-options",
               '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}',
               "--instance-initiated-shutdown-behavior", "terminate", "--block-device-mappings",
               f'[{{"DeviceName":"/dev/xvda","Ebs":{{"VolumeSize":{root_gb},"VolumeType":"gp3"}}}}]',
               "--user-data", f"file://{userdata_path}", "--tag-specifications",
               f"ResourceType=instance,Tags=[{{Key=Name,Value={name}}},{{Key=project,Value=cyclic-selector}}]",
               "--query", "Instances[0].InstanceId", "--output", "text", "--cli-read-timeout", "60", "--cli-connect-timeout", "10"]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip().startswith("i-"):
            iid = r.stdout.strip()
            new = not os.path.exists(COST_LOG)
            with open(COST_LOG, "a", newline="") as f:
                w = csv.writer(f)
                if new:
                    w.writerow(["utc_launch", "instance_id", "type", "name", "subnet", "note"])
                w.writerow([time.strftime("%FT%TZ", time.gmtime()), iid, itype, name, sub, "spot"])
            return iid
        last = (r.stderr or r.stdout)[-300:]
    raise RuntimeError("no spot capacity / launch failed: " + last)


if __name__ == "__main__":
    # usage: python3 -m orchestrator.ec2 <workstream> <run_id> "<command>" [wall_min] [itype]
    ws, rid, cmd = sys.argv[1], sys.argv[2], sys.argv[3]
    wall = int(sys.argv[4]) if len(sys.argv) > 4 else 60
    itype = sys.argv[5] if len(sys.argv) > 5 else "c6i.large"
    pref = run_prefix(ws, rid)
    upload_code(pref)
    ud = os.path.join("/tmp", f"ud_{ws}_{rid}.sh")
    open(ud, "w").write(make_userdata(pref, cmd, wall))
    print(pref, launch(ud, f"allatom-{ws}"), flush=True)
