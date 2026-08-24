set -uo pipefail
source /opt/conda/etc/profile.d/conda.sh && conda activate omtps
export WANDB_MODE=offline MPLBACKEND=Agg
cd /opt/OM-TPS/two-for-one-diffusion
cp -n datasets/ala2/data/ala2.pdb datasets/folded_pdbs/ala2.pdb
mkdir -p /data/sanjeevr && ( cd /data/sanjeevr && aws s3 cp s3://biomate-nextflow-work/builds/omtps-ctx/data/Ala2Train.zip . --region us-west-2 && unzip -q -o Ala2Train.zip && rm -f Ala2Train.zip )
aws s3 cp s3://biomate-nextflow-work/builds/omtps-ctx/m6_patch.py /tmp/m6_patch.py --region us-west-2
aws s3 cp s3://biomate-nextflow-work/builds/omtps-ctx/build_ala_density.py ./build_ala_density.py --region us-west-2
python /tmp/m6_patch.py models/flow_matching.py
python build_ala_density.py
export M6_DENSITY_NPZ=/tmp/ala_density.npz
echo "== GUIDED om_interpolate (alanine) lam=$M6_DENSITY_LAM =="
python sample.py --model_path saved_models/alanine_dipeptide --gen_mode om_interpolate \
  --atom_selection protein --num_samples_eval 8 --batch_size_gen 2 --latent_time 30 \
  --initial_guess_level 300 --no_encode_and_decode --action truncated --optimizer adam \
  --lr 3e-3 --om_dt 0.0001 --om_gamma 0.7 --path_length 300 --path_batch_size 300 --steps 5000 \
  --append_exp_name guided_lam${M6_DENSITY_LAM} 2>&1 | tee /tmp/run.log
RC=${PIPESTATUS[0]}
aws s3 cp /tmp/run.log s3://biomate-nextflow-work/builds/omtps/run/guided_lam${M6_DENSITY_LAM}.log --region us-west-2 || true
for d in saved_models/alanine_dipeptide/main_eval_output*guided_lam${M6_DENSITY_LAM}*; do
  aws s3 cp "$d/" s3://biomate-nextflow-work/builds/omtps/run/results_guided_lam${M6_DENSITY_LAM}/ --recursive --exclude "*.pt" --region us-west-2 || true
done
echo "SAMPLE_RC=$RC"; exit $RC
