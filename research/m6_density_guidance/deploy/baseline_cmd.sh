set -uo pipefail
source /opt/conda/etc/profile.d/conda.sh && conda activate omtps
export WANDB_MODE=offline MPLBACKEND=Agg
cd /opt/OM-TPS/two-for-one-diffusion
cp -n datasets/ala2/data/ala2.pdb datasets/folded_pdbs/ala2.pdb
# GT trajectory (defines alanine transition endpoints) at the code's hardcoded path
mkdir -p /data/sanjeevr
( cd /data/sanjeevr && aws s3 cp s3://biomate-nextflow-work/builds/omtps-ctx/data/Ala2Train.zip . --region us-west-2 && unzip -q -o Ala2Train.zip && rm -f Ala2Train.zip )
echo "GT files:"; ls -la /data/sanjeevr/Ala2Train/ 2>&1 | head
python -c "import torch;print('cuda',torch.cuda.is_available(),torch.__version__)"
echo "== BASELINE om_interpolate (alanine) =="
python sample.py --model_path saved_models/alanine_dipeptide --gen_mode om_interpolate \
  --atom_selection protein --num_samples_eval 8 --batch_size_gen 2 --latent_time 30 \
  --initial_guess_level 300 --no_encode_and_decode --action truncated --optimizer adam \
  --lr 3e-3 --om_dt 0.0001 --om_gamma 0.7 --path_length 300 --path_batch_size 300 --steps 5000 2>&1 | tee /tmp/run.log
RC=${PIPESTATUS[0]}
aws s3 cp /tmp/run.log s3://biomate-nextflow-work/builds/omtps/run/baseline_run.log --region us-west-2 || true
aws s3 cp saved_models/alanine_dipeptide/ s3://biomate-nextflow-work/builds/omtps/run/results/ --recursive --exclude "*.pt" --region us-west-2 || true
echo "SAMPLE_RC=$RC"; exit $RC
