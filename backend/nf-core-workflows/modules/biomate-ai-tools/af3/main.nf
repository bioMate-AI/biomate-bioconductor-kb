// AlphaFold 3 structure prediction module
// Inputs: JSON input file (AF3 fold_input.json format) + model weights from S3
// Outputs: predicted structures (.cif), confidence scores, ranking summary

nextflow.enable.dsl=2

process AF3_PREDICT {
    tag "$meta.id"
    label 'process_gpu'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/af3-nf:v1.0.1'

    input:
    tuple val(meta), path(fold_input_json)
    val  model_s3_path        // e.g. s3://biomate-nextflow-work/models/af3/
    val  db_s3_path           // e.g. s3://biomate-nextflow-work/databases/af3/ (optional)
    val  num_seeds            // number of random seeds (default 5)
    val  run_data_pipeline    // true = run MSA/template search; false = skip (no DB needed)

    output:
    tuple val(meta), path("af3_output/${meta.id}/"), emit: results
    tuple val(meta), path("af3_output/${meta.id}/ranking_scores.csv"), emit: ranking
    path "versions.yml", emit: versions

    script:
    def prefix        = task.ext.prefix ?: "${meta.id}"
    def n_seeds       = num_seeds ?: 5
    def run_data_pipe = run_data_pipeline != false ? 'true' : 'false'
    def db_flag       = (run_data_pipe == 'true' && db_s3_path) ? "--db_dir=/tmp/af3_db" : ""
    """
    set -euo pipefail

    # ── Download model weights ─────────────────────────────────────────────────
    echo "[AF3] Downloading model weights from ${model_s3_path}"
    mkdir -p /tmp/af3_model
    aws s3 cp --region us-west-2 "${model_s3_path}" /tmp/af3_model/af3.bin
    echo "[AF3] Weights downloaded: \$(du -sh /tmp/af3_model/af3.bin | cut -f1)"

    # ── Optionally download databases ──────────────────────────────────────────
    if [[ "${run_data_pipe}" == "true" && -n "${db_s3_path}" ]]; then
        echo "[AF3] Syncing databases from ${db_s3_path}"
        mkdir -p /tmp/af3_db
        aws s3 sync --region us-west-2 "${db_s3_path}" /tmp/af3_db/ --quiet
    fi

    # ── Run AF3 inference ──────────────────────────────────────────────────────
    # XLA flag required for Volta-class GPUs (V100, sm_70) — AF3 uses Triton
    # kernels that need custom-kernel-fusion-rewriter disabled on compute cap 7.x.
    export XLA_FLAGS="\${XLA_FLAGS:-} --xla_disable_hlo_passes=custom-kernel-fusion-rewriter"
    mkdir -p af3_output
    python3 /opt/alphafold3/run_alphafold.py \\
        --json_path="${fold_input_json}" \\
        --model_dir=/tmp/af3_model \\
        --output_dir=af3_output \\
        --num_diffusion_samples=${n_seeds} \\
        --run_data_pipeline=${run_data_pipe} \\
        --run_inference=true \\
        ${db_flag} \\
        2>&1

    echo "[AF3] Inference complete"
    ls af3_output/*/

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        alphafold3: 3.0.1
        jax: \$(python3 -c "import jax; print(jax.__version__)")
        python: \$(python3 --version | awk '{print \$2}')
    END_VERSIONS
    """
}
