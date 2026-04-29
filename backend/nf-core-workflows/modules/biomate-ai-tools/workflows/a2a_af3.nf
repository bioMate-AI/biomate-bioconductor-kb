#!/usr/bin/env nextflow
/*
 * A2A AlphaFold3 Conformational Sampling Pilot
 *
 * Uses pre-computed ColabFold MSA (8,873 uniref + 5,761 BFD/MGnify homologs)
 * skipping the 630 GB local database requirement via --norun_data_pipeline.
 *
 * AF3 weights required: request at github.com/google-deepmind/alphafold3
 * Upload weights to: s3://biomate-nextflow-work/models/af3_weights/
 *
 * GPU requirement: A100 80 GB (p4d.24xlarge) or A100 40 GB for <=448 aa.
 */
nextflow.enable.dsl=2

params.af3_input   = 's3://biomate-nextflow-work/pilot/af3_inputs/a2a_af3_input.json'
params.weights_dir = 's3://biomate-nextflow-work/models/af3_weights'
params.n_seeds     = 50
params.outdir      = 's3://biomate-nextflow-work/pilot/results/a2a-af3'

process AF3_CONFORMERS {
    tag "a2a_af3"
    label 'process_gpu'

    // AF3 needs 80 GB VRAM for long seqs; A2A is 448 aa → fits in 40 GB
    // Route to p4d queue when available; fall back to A100 40 GB on g5.12xlarge
    queue         = 'biomate-a100-queue'
    cpus          = 8
    memory        = '60.GB'
    accelerator   = 1
    time          = '6.h'

    container 'us-docker.pkg.dev/deepmind-platform-rapid/alphafold3-docker/alphafold3:latest'

    publishDir "${params.outdir}", mode: 'copy'

    input:
    path af3_json
    val  weights_dir

    output:
    path "af3_ensemble.tar.gz", emit: ensemble
    path "af3_outputs/",        emit: raw_outputs
    path "versions.yml",        emit: versions

    script:
    """
    # Download AF3 weights from S3 (model weights ~1 GB, not databases)
    mkdir -p af3_weights
    aws s3 sync --quiet --region us-west-2 ${weights_dir} af3_weights/

    # Run AF3 with pre-computed MSA — skip 630 GB data pipeline
    python /app/alphafold3/run_alphafold.py \\
        --json_path=${af3_json} \\
        --model_dir=af3_weights/ \\
        --output_dir=af3_outputs/ \\
        --norun_data_pipeline \\
        --num_diffusion_samples=${params.n_seeds}

    # Collect all PDB outputs into ensemble tarball
    python3 - << 'PYEOF'
import glob, os, tarfile, shutil

os.makedirs("ensemble_pdbs", exist_ok=True)
pdbs = sorted(glob.glob("af3_outputs/**/*.pdb", recursive=True))
print(f"AF3 generated {len(pdbs)} conformers")
for i, p in enumerate(pdbs):
    shutil.copy(p, f"ensemble_pdbs/conf_{i:04d}.pdb")

with tarfile.open("af3_ensemble.tar.gz", "w:gz") as tf:
    tf.add("ensemble_pdbs", arcname=".")
print(f"Packed {len(pdbs)} conformers into af3_ensemble.tar.gz")
PYEOF

    python3 -c "
print('AF3_CONFORMERS:')
print('    alphafold3: 3.0.0')
print('    msa_source: ColabFold_API')
print('    n_homologs_uniref: 8873')
print('    n_homologs_bfd: 5761')
print('    run_data_pipeline: false')
" > versions.yml
    """
}

workflow {
    json_ch    = Channel.value(file(params.af3_input))
    AF3_CONFORMERS(json_ch, params.weights_dir)
}
