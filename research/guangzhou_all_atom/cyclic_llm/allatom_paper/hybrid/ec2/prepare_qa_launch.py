"""Prepare (never launch) one bounded AWS CPU Spot QA request.

Usage: python prepare_qa_launch.py BUNDLE_S3 BUNDLE_SHA256 RUN_ID OUTPUT_DIR
Provision only after budget approval. Operator must terminate a worker that has
not stopped by 30 minutes from launch; userdata schedules shutdown at 25 minutes.
"""
import argparse
import base64
import json
from pathlib import Path
import re
import shlex


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle_s3'); parser.add_argument('bundle_sha256')
    parser.add_argument('run_id'); parser.add_argument('output_dir')
    args=parser.parse_args()
    allowed='s3://biomate-nextflow-work/cyclic_peptide/allatom/'
    if not args.bundle_s3.startswith(allowed):raise ValueError('project S3 bundle required')
    if not re.fullmatch('[0-9a-f]{64}',args.bundle_sha256):raise ValueError('invalid SHA256')
    if not re.fullmatch('[a-z0-9-]{1,45}',args.run_id):raise ValueError('invalid unique run ID')
    out=Path(args.output_dir);out.mkdir(parents=True,exist_ok=False)
    prefix=allowed+'integration_qa/'+args.run_id
    body=r'''#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
/sbin/shutdown -h +25
mkdir -p /w/code /w/logs
exec > >(tee -a /w/logs/boot.log) 2>&1
PREFIX=__PREFIX__
aws s3 cp /w/logs/boot.log "$PREFIX/boot.log" --only-show-errors --cli-connect-timeout 5 --cli-read-timeout 10 || true
sync_logs() {
  aws s3 sync /w/logs "$PREFIX/logs/" --only-show-errors --cli-connect-timeout 5 --cli-read-timeout 10 || true
  if [[ -d /w/out ]]; then
    aws s3 sync /w/out "$PREFIX/out/" --exclude '*/venv/*' --only-show-errors --cli-connect-timeout 5 --cli-read-timeout 10 || true
  fi
}
finish() {
  rc=$?
  trap - EXIT
  printf '%s\n' "$rc" > /w/logs/bootstrap_exit_code.txt
  if [[ -n ${sync_pid:-} ]]; then kill "$sync_pid" 2>/dev/null || true; fi
  sync_logs
  /sbin/shutdown -h now
  exit "$rc"
}
trap finish EXIT
trap 'exit 124' TERM
(while sleep 30; do sync_logs; done) &
sync_pid=$!
timeout 300 dnf -y install python3.11 python3.11-pip
aws s3 cp __BUNDLE__ /w/bundle.tar.gz --only-show-errors
printf '%s  %s\n' __SHA__ /w/bundle.tar.gz | sha256sum --check -
tar -xzf /w/bundle.tar.gz -C /w/code
export METHOD_QA_PYTHON=python3.11
bash /w/code/cyclic_llm/allatom_paper/hybrid/ec2/qa_integration.sh /w/code/cyclic_llm /w/out/integration-qa
'''
    for marker,value in [('__PREFIX__',prefix),('__BUNDLE__',args.bundle_s3),('__SHA__',args.bundle_sha256)]:
        body=body.replace(marker,shlex.quote(value))
    (out/'userdata.sh').write_text(body)
    request=dict(ImageId='ami-0829b74b2a8c619b7',InstanceType='c6i.xlarge',MinCount=1,MaxCount=1,
        ClientToken=args.run_id,IamInstanceProfile={'Name':'ecsInstanceRole'},
        InstanceMarketOptions={'MarketType':'spot','SpotOptions':{'MaxPrice':'0.10','SpotInstanceType':'one-time','InstanceInterruptionBehavior':'terminate'}},
        InstanceInitiatedShutdownBehavior='terminate',
        NetworkInterfaces=[dict(DeviceIndex=0,SubnetId='subnet-0b35a6e2c1cf02dc2',Groups=['sg-0de9af2d4437a8c90'],AssociatePublicIpAddress=True)],
        MetadataOptions={'HttpTokens':'required','HttpEndpoint':'enabled'},
        BlockDeviceMappings=[{'DeviceName':'/dev/xvda','Ebs':{'VolumeSize':40,'VolumeType':'gp3','DeleteOnTermination':True,'Encrypted':True}}],
        TagSpecifications=[{'ResourceType':kind,'Tags':[{'Key':'Name','Value':'allatom-'+args.run_id},{'Key':'project','Value':'cyclic-selector'}]} for kind in ('instance','volume')],
        UserData=base64.b64encode(body.encode()).decode())
    (out/'launch.json').write_text(json.dumps(request,indent=2)+'\n')
    print(json.dumps(dict(status='PREPARED_ONLY',launch=str(out/'launch.json'),s3_prefix=prefix)))


if __name__=='__main__':main()
