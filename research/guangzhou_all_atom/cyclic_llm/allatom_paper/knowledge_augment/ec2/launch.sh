#!/bin/bash
# usage: launch.sh USERDATA.sh [NAME]  -> spot instance (GPU types first, then CPU fallback via CPU_FALLBACK=1); appends to ../ka_cost_log.csv
UD=$1; NAME=${2:-allatom-ka}; LOG="$(dirname "$0")/../ka_cost_log.csv"
SUBS="subnet-0254e4c3634b41bfc subnet-09e4dce46682a6c60 subnet-0b35a6e2c1cf02dc2 subnet-03b277a7a08d388c1"
if [ -n "$CPU_FALLBACK" ]; then TYPES="c6i.4xlarge c5.4xlarge m6i.4xlarge"; AMI=ami-0829b74b2a8c619b7; else TYPES="${GPU_TYPES:-g5.xlarge g6.xlarge g5.2xlarge g6.2xlarge}"; AMI=ami-0b5dd351f8c2cb541; fi
for t in $TYPES; do for sub in $SUBS; do
 IID=$(aws ec2 run-instances --image-id $AMI --instance-type $t --subnet-id $sub --security-group-ids sg-0de9af2d4437a8c90 --iam-instance-profile Name=ecsInstanceRole \
   --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}' --instance-initiated-shutdown-behavior terminate \
   --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":100,"VolumeType":"gp3"}}]' --user-data file://$UD \
   --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=project,Value=cyclic-selector}]" --query 'Instances[0].InstanceId' --output text --cli-read-timeout 60 2>/dev/null) && [ -n "$IID" ] && [ "$IID" != None ] && { echo "$IID $t $sub"; [ -f "$LOG" ] || echo "instance_id,type,launch_utc,name" > "$LOG"; echo "$IID,$t,$(date -u +%FT%TZ),$NAME" >> "$LOG"; exit 0; }
done; done; echo NO_CAPACITY; exit 1
