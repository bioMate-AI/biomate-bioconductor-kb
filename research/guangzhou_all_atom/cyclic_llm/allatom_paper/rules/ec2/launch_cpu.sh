#!/bin/bash
# usage: launch_cpu.sh USERDATA.sh NAME "TYPES"   -> spot CPU (AL2023, ecsInstanceRole); appends to ../u1_cost_log.csv
UD=$1; NAME=$2; TYPES=${3:-"c6i.8xlarge c5.9xlarge m6i.8xlarge c6a.8xlarge"}
for t in $TYPES; do for sub in subnet-0254e4c3634b41bfc subnet-09e4dce46682a6c60 subnet-0b35a6e2c1cf02dc2 subnet-03b277a7a08d388c1; do
 IID=$(aws ec2 run-instances --image-id ami-0829b74b2a8c619b7 --instance-type $t --subnet-id $sub --security-group-ids sg-0de9af2d4437a8c90 --iam-instance-profile Name=ecsInstanceRole \
   --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}' --instance-initiated-shutdown-behavior terminate \
   --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":60,"VolumeType":"gp3"}}]' --user-data file://$UD \
   --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=project,Value=cyclic-selector}]" --query 'Instances[0].InstanceId' --output text --cli-read-timeout 60 2>/dev/null) && [ -n "$IID" ] && { echo "$IID $t $sub"; echo "$IID $t $(date -u +%FT%TZ) $NAME" >> "$(dirname "$0")/../u1_cost_log.csv"; exit 0; }
done; done; echo NO_CAPACITY; exit 1
