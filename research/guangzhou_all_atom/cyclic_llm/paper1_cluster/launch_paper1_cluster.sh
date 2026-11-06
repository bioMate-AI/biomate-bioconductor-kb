#!/bin/bash
# Launch the paper-1 cluster-interval job on EC2 spot (nothing is computed on the launching machine).
# usage: launch_paper1_cluster.sh RUN_ID     (default run1). One writer per S3 prefix: s3://.../paper1_cluster/<RUN_ID>/
set -u
RUN=${1:-run1}; B=s3://biomate-nextflow-work/cyclic_peptide; P=$B/paper1_cluster/$RUN
HERE=$(cd "$(dirname "$0")" && pwd); LLM=$(cd "$HERE/.." && pwd); TMP=$(mktemp -d)
( cd "$LLM/.." && tar czf "$TMP/code.tgz" cyclic_llm/loop_retro/*.py cyclic_llm/ihlm_ladder/*.py cyclic_llm/paper1_cluster/*.py cyclic_llm/medchem_kb.py ) || exit 1
aws s3 cp "$TMP/code.tgz" $P/code.tgz --only-show-errors --cli-read-timeout 60 || exit 1
cat > "$TMP/ud.sh" <<EOF
#!/bin/bash
B=$B; P=$P
shutdown -h +60
exec > >(tee /var/log/job.log) 2>&1
( while true; do aws s3 cp /var/log/job.log \$P/boot.log --only-show-errors; sleep 20; done ) &
BG=\$!
dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/dev/null 2>&1
python3.11 -m pip install -q numpy scipy scikit-learn rdkit >/dev/null 2>&1
mkdir -p /w/code /w/ladder /w/l7 /w/out && cd /w
aws s3 cp \$P/code.tgz . --only-show-errors && tar xzf code.tgz -C /w/code
aws s3 cp \$B/loop_retro/data/CycPeptMPDB_Peptide_All.csv /w/ --only-show-errors
aws s3 sync \$B/ihlm_ladder/res/ /w/ladder/ --only-show-errors
for p in \$(aws s3 ls \$B/loop_retro/ | awk '/PRE res7[a-z]_/ && !/_llm\\//{print \$2}' | tr -d '/'); do mkdir -p /w/l7/\$p; aws s3 sync \$B/loop_retro/\$p/ /w/l7/\$p/ --exclude "*.log" --exclude "*.flag" --only-show-errors; done
echo "files: ladder \$(ls /w/ladder | wc -l) l7dirs \$(ls /w/l7 | wc -l)"
cd /w/code/cyclic_llm/paper1_cluster
python3.11 paper1_cluster.py /w/CycPeptMPDB_Peptide_All.csv /w/ladder /w/l7 /w/out/paper1_cluster > /w/run.log 2>&1; echo "rc=\$?" >> /w/run.log
aws s3 cp /w/out/ \$P/out/ --recursive --only-show-errors
aws s3 cp /w/run.log \$P/run.log --only-show-errors
echo DONE > /w/done; aws s3 cp /w/done \$P/done.flag --only-show-errors
kill \$BG; aws s3 cp /var/log/job.log \$P/boot.log --only-show-errors
shutdown -h now
EOF
for sub in subnet-0b35a6e2c1cf02dc2 subnet-03b277a7a08d388c1 subnet-09e4dce46682a6c60 subnet-0254e4c3634b41bfc; do
  for t in c6i.2xlarge c5.2xlarge m6i.2xlarge; do
    IID=$(aws ec2 run-instances --image-id ami-0829b74b2a8c619b7 --instance-type $t --subnet-id $sub --security-group-ids sg-0de9af2d4437a8c90 \
      --iam-instance-profile Name=ecsInstanceRole --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}' \
      --instance-initiated-shutdown-behavior terminate --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":40,"VolumeType":"gp3"}}]' \
      --user-data file://$TMP/ud.sh --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=paper1-cluster},{Key=project,Value=cyclic-selector}]" \
      --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "$IID $t $sub $(date -u +%FT%TZ)"; exit 0; }
  done
done
echo "NO CAPACITY"; exit 2
