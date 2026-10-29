#!/bin/bash
# Pilot 5 stage launcher (EC2 spot only; owner rule: no experiment compute on the laptop).
# usage: launch_stage.sh STAGE   with STAGE in select | A | B
#   select : wait for 200 fits on S3, run inner selection p5select 0 20, upload configs
#   A      : baseline-only outer pass + MDE (needs FROZEN configs uploaded to run1/configs_frozen/ from the COMMITTED repo)
#   B      : H5/H5NN outer pass + controls + gate (needs A's outer files from run1/stage_A/ and the committed mde.json)
set -u
STAGE=$1; B=s3://biomate-nextflow-work/cyclic_peptide/ihlm_pilot5; HERE="$(cd "$(dirname "$0")" && pwd)"
UD=$(mktemp); cat > $UD <<UDEOF
#!/bin/bash
B=$B; STAGE=$STAGE; P=stage_\$STAGE
shutdown -h +150
exec > >(tee /w_boot.log) 2>&1
dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/dev/null 2>&1
python3.11 -m pip install -q numpy pandas scipy scikit-learn joblib >/dev/null 2>&1
R=/w/repo/research/guangzhou_all_atom; mkdir -p \$R/cyclic_llm/ihlm_backbone/pilot4/results \$R/cyclic_llm/ihlm_backbone/pilot5/results \$R/multitarget/integrin_chembl/retro_recovery/data /w/out
aws s3 cp \$B/data/fp.npy \$R/cyclic_llm/ihlm_backbone/pilot4/results/fp.npy --only-show-errors
aws s3 cp \$B/data/rr/ \$R/multitarget/integrin_chembl/retro_recovery/data/ --recursive --only-show-errors
aws s3 cp \$B/data/eval/ \$R/cyclic_llm/ihlm_backbone/pilot4/results/ --recursive --only-show-errors
aws s3 cp \$B/code/p4common.py \$R/cyclic_llm/ihlm_backbone/pilot4/ --only-show-errors
aws s3 cp \$B/code2/ \$R/cyclic_llm/ihlm_backbone/pilot5/ --recursive --only-show-errors
cd \$R/cyclic_llm/ihlm_backbone/pilot5; RES=\$PWD/results; NP=\$(nproc --all); export OMP_NUM_THREADS=1
echo "boot ok \$(date -u) nproc=\$NP stage=\$STAGE"; aws s3 cp /w_boot.log \$B/run1/\$P/boot.log --only-show-errors
mkdir -p /w/out/configs /w/out/outer; aws s3 sync \$B/run1/\$P/configs/ \$RES/configs/ --only-show-errors; aws s3 sync \$B/run1/\$P/outer/ \$RES/ --only-show-errors   # resume after a spot reclaim: restore this stage's own earlier outputs
( while true; do cp -u \$RES/configs/*.json /w/out/configs/ 2>/dev/null; cp -u \$RES/outer_\${STAGE}_r*_f*.csv.gz /w/out/outer/ 2>/dev/null; aws s3 sync /w/out \$B/run1/\$P/ --only-show-errors; aws s3 cp /w_boot.log \$B/run1/\$P/boot.log --only-show-errors; sleep 60; done ) &
SYNC=\$!
case \$STAGE in
 select)
  for i in \$(seq 1 150); do n=\$(aws s3 ls \$B/run1/fits/ | grep -c 'npz\$'); echo "fits on S3: \$n"; [ "\$n" -ge 200 ] && break; sleep 60; done
  [ "\$n" -ge 200 ] || { echo "FITS INCOMPLETE (\$n)"; touch /w/out/FAILED_fits_incomplete; kill \$SYNC; aws s3 sync /w/out \$B/run1/\$P/ --only-show-errors; shutdown -h now; exit 3; }
  aws s3 sync \$B/run1/fits/ \$RES/fits/ --only-show-errors
  python3.11 p5select.py 0 20 --jobs \$NP > /w/out/select.log 2>&1; echo "select rc=\$?" >> /w/out/select.log
  mkdir -p /w/out/configs; cp \$RES/configs/*.json /w/out/configs/ ;;
 A)
  aws s3 sync \$B/run1/fits/ \$RES/fits/ --only-show-errors; aws s3 sync \$B/run1/configs_frozen/ \$RES/configs/ --only-show-errors
  python3.11 p5outer.py A 0 20 --jobs \$NP > /w/out/outer_A.log 2>&1; echo "outerA rc=\$?" >> /w/out/outer_A.log
  python3.11 p5agg.py mde > /w/out/mde.log 2>&1; echo "mde rc=\$?" >> /w/out/mde.log
  mkdir -p /w/out/outer; cp \$RES/outer_A_*.csv.gz /w/out/outer/; cp \$RES/mde.json /w/out/ ;;
 B)
  aws s3 sync \$B/run1/fits/ \$RES/fits/ --only-show-errors; aws s3 sync \$B/run1/configs_frozen/ \$RES/configs/ --only-show-errors
  aws s3 sync \$B/run1/stage_A/outer/ \$RES/ --only-show-errors; aws s3 cp \$B/run1/mde_frozen/mde.json \$RES/mde.json --only-show-errors
  python3.11 p5outer.py B 0 20 --jobs \$NP > /w/out/outer_B.log 2>&1; echo "outerB rc=\$?" >> /w/out/outer_B.log
  python3.11 p5controls.py --jobs \$NP > /w/out/controls.log 2>&1; echo "controls rc=\$?" >> /w/out/controls.log
  python3.11 p5agg.py gate > /w/out/gate.log 2>&1; echo "gate rc=\$?" >> /w/out/gate.log
  mkdir -p /w/out/outer; cp \$RES/outer_B_*.csv.gz /w/out/outer/; cp \$RES/gate_summary.json \$RES/controls_summary.json \$RES/controls.csv.gz /w/out/ ;;
esac
touch /w/out/DONE; kill \$SYNC; aws s3 sync /w/out \$B/run1/\$P/ --only-show-errors; aws s3 cp /w_boot.log \$B/run1/\$P/boot.log --only-show-errors; shutdown -h now
UDEOF
for t in c6i.8xlarge c5.9xlarge c6a.8xlarge m6i.8xlarge; do for sub in subnet-0b35a6e2c1cf02dc2 subnet-03b277a7a08d388c1 subnet-09e4dce46682a6c60 subnet-0254e4c3634b41bfc; do
 IID=$(aws ec2 run-instances --image-id ami-0829b74b2a8c619b7 --instance-type $t --subnet-id $sub --security-group-ids sg-0de9af2d4437a8c90 --iam-instance-profile Name=ecsInstanceRole --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}' --instance-initiated-shutdown-behavior terminate --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":40,"VolumeType":"gp3"}}]' --user-data file://$UD --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ihlm-pilot5-$STAGE},{Key=project,Value=cyclic-selector}]" --query 'Instances[0].InstanceId' --output text --cli-read-timeout 60 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED $STAGE $t $sub $IID $(date -u +%FT%TZ)"; exit 0; }; done; done; echo "NO CAPACITY"; exit 1
