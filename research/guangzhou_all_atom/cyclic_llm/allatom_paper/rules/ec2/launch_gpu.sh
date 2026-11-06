#!/bin/bash
# usage: launch_gpu.sh USERDATA.sh NAME   -> spot GPU (DLAMI PyTorch 2.13, ecsInstanceRole); tries types x subnets; prints the instance id; appends to ../u1_cost_log.csv
UD=$1; NAME=$2
for t in ${GPU_TYPES:-g5.2xlarge g5.xlarge g6.xlarge g6.2xlarge g5.4xlarge g6.4xlarge g6e.xlarge g6e.2xlarge g5.8xlarge g6.8xlarge}; do for sub in subnet-0254e4c3634b41bfc subnet-09e4dce46682a6c60 subnet-0b35a6e2c1cf02dc2 subnet-03b277a7a08d388c1; do
 IID=$(aws ec2 run-instances --image-id ami-0b5dd351f8c2cb541 --instance-type $t --subnet-id $sub --security-group-ids sg-0de9af2d4437a8c90 --iam-instance-profile Name=ecsInstanceRole \
   --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}' --instance-initiated-shutdown-behavior terminate \
   --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":120,"VolumeType":"gp3"}}]' --user-data file://$UD \
   --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=project,Value=cyclic-selector}]" --query 'Instances[0].InstanceId' --output text --cli-read-timeout 60 2>/dev/null) && [ -n "$IID" ] && { echo "$IID $t $sub"; echo "$IID $t $(date -u +%FT%TZ) $NAME" >> "$(dirname "$0")/../u1_cost_log.csv"; exit 0; }
done; done; echo NO_CAPACITY; exit 1
