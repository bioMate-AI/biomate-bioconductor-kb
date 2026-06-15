#!/usr/bin/env nextflow

/**
 * boltz_structure_prediction
 *
 * Biomolecular structure prediction using Boltz-2 (MIT licensed).
 * Predicts structures of proteins, RNA, DNA, ligands, and protein-ligand complexes
 * with binding affinity estimates. 1000x faster than physics-based FEP.
 *
 * Inputs:
 *   params.input_fasta   -- FASTA file (protein/RNA/DNA sequences)
 *   params.input_yaml    -- Boltz YAML input (overrides fasta; for complexes/ligands)
 *   params.use_msa_server -- use ColabFold MSA server (default: true)
 *   params.sampling_steps -- diffusion sampling steps (default: 200)
 *   params.output_format  -- 'pdb' | 'mmcif' (default: 'mmcif')
 *   params.recycling_steps -- recycling steps (default: 3)
 *   params.outdir        -- output directory (default: 'results')
 */

nextflow.enable.dsl = 2

params.input_fasta     = ''
params.input_yaml      = ''
params.use_msa_server  = true
params.sampling_steps  = 200
params.recycling_steps = 3
params.output_format   = 'mmcif'
params.outdir          = 'results'
params.publish_dir_mode = 'copy'

def ECR = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:latest'

// -- Prepare input ------------------------------------------------------------

process PREPARE_INPUT {
    tag "prepare"
    label 'process_low'
    container ECR

    input:
    path(input_file)

    output:
    path("boltz_input.*"), emit: input_file

    script:
    // Real file — pick destination extension by source. Avoids the NO_FILE
    // placeholder pattern (which AWS Batch can't stage — no physical file).
    def dst = input_file.name.toLowerCase().endsWith('.yaml') || input_file.name.toLowerCase().endsWith('.yml')
        ? 'boltz_input.yaml'
        : 'boltz_input.fasta'
    """
    cp ${input_file} ${dst}
    """
}

// -- Run Boltz-2 prediction ----------------------------------------------------

process BOLTZ_PREDICT {
    tag "boltz2"
    label 'process_gpu'
    publishDir { "${params.outdir}/structures" }, mode: 'copy'

    container ECR

    input:
    path(input_file)

    output:
    path("boltz_results/"), emit: results_dir
    path("boltz_results/**/*.${params.output_format}"), emit: structures, optional: true
    path("boltz_results/**/confidence_*.json"), emit: confidence, optional: true

    script:
    def msa_flag = params.use_msa_server ? '--use_msa_server' : ''
    """
    boltz predict ${input_file} \\
        --out_dir boltz_results/ \\
        --output_format ${params.output_format} \\
        --sampling_steps ${params.sampling_steps} \\
        --recycling_steps ${params.recycling_steps} \\
        ${msa_flag} \\
        --accelerator gpu \\
        --devices 1
    """
}

// -- Summarise results --------------------------------------------------------

process BOLTZ_SUMMARISE_RESULTS {
    tag "summary"
    label 'process_low'
    publishDir { "${params.outdir}" }, mode: 'copy'

    container ECR

    input:
    path(results_dir)

    output:
    path("boltz_summary.json"),  emit: summary
    path("qc_metrics.json"),     emit: qc_metrics

    script:
    """
    python3 - <<'EOF'
import json, glob, os

structures = glob.glob("${results_dir}/**/*.mmcif", recursive=True) + \
             glob.glob("${results_dir}/**/*.pdb", recursive=True)
confidence_files = glob.glob("${results_dir}/**/confidence_*.json", recursive=True)

confidence_data = []
for f in confidence_files:
    with open(f) as fh:
        confidence_data.append({"file": os.path.basename(f), "scores": json.load(fh)})

summary = {
    "tool": "Boltz-2",
    "version": "2.2.1",
    "structures_predicted": len(structures),
    "structure_files": [os.path.basename(s) for s in structures],
    "confidence_scores": confidence_data,
}
with open("boltz_summary.json", "w") as f:
    json.dump(summary, f, indent=2)
print(json.dumps(summary, indent=2))

# qc_metrics.json — gate metrics consumed by the QC monitor's
# structure-prediction gates (Jumper 2021 / Tunyasuvunakool 2021):
#   mean_plddt           ≥ 70 → downstream-docking ready (GOLD)
#   confident_fraction   ≥ 0.70 → bulk of model well-modelled (SILVER)
#   max_pae              ≤ 8 Å inter-domain (SILVER, skipped when None)
# Boltz output keys vary by version; defensively extract whatever the
# top-ranked confidence file reports.
mean_plddt = None
confident_fraction = None
max_pae = None
if confidence_data:
    top = confidence_data[0]["scores"]
    for k in ("complex_plddt", "mean_plddt", "plddt_mean", "plddt", "ptm_iptm_global_plddt"):
        if k in top and top[k] is not None:
            mean_plddt = float(top[k])
            break
    for k in ("confident_fraction", "frac_plddt_gt_70", "plddt_confident_frac"):
        if k in top and top[k] is not None:
            confident_fraction = float(top[k])
            break
    for k in ("max_pae", "pae_max", "complex_pae"):
        if k in top and top[k] is not None:
            v = top[k]
            max_pae = float(v) if not isinstance(v, list) else float(max(max(row) for row in v))
            break

qc_metrics = {
    "mean_plddt":         round(mean_plddt, 2) if mean_plddt is not None else None,
    "confident_fraction": round(confident_fraction, 3) if confident_fraction is not None else None,
    "max_pae":            round(max_pae, 2) if max_pae is not None else None,
    "structures_predicted": len(structures),
    "tool":               "Boltz-2",
}

# ── QC gates: struct_pred_confident_fraction + struct_pred_max_pae ────────
# Track 2 batch 2 (2026-06-15): wire pass-band fields for both structure-
# prediction gates documented in qc_evidence.yaml structure_prediction.
#   struct_pred_confident_fraction (SILVER, Tunyasuvunakool 2021):
#       confident_fraction (frac residues pLDDT > 70) ≥ 0.70 → pass
#   struct_pred_max_pae (SILVER, Tunyasuvunakool 2021):
#       max inter-domain PAE ≤ 8 Å → pass; skipped (treated as pass) when
#       max_pae is None (single-domain proteins per the YAML rule_text).
# All booleans wrapped in bool(...) per f516fd12 numpy-bool fix.
qc_metrics["confident_fraction_threshold"] = 0.70
qc_metrics["struct_pred_confident_fraction_passes"] = bool(
    confident_fraction is not None and confident_fraction >= 0.70
)
qc_metrics["max_pae_threshold"] = 8.0
qc_metrics["struct_pred_max_pae_passes"] = bool(
    max_pae is None or max_pae <= 8.0
)
with open("qc_metrics.json", "w") as f:
    json.dump(qc_metrics, f, indent=2)
EOF
    """
}

// -- Workflow ----------------------------------------------------------------

workflow {
    // Pick whichever real input was supplied — YAML wins if both set.
    // Avoids the NO_FILE placeholder channel which AWS Batch can't stage.
    if (!params.input_fasta && !params.input_yaml) {
        error "Please provide --input_fasta or --input_yaml (one is required)"
    }
    def input_path = params.input_yaml ?: params.input_fasta
    input_ch = Channel.fromPath(input_path, checkIfExists: true)

    PREPARE_INPUT(input_ch)
    BOLTZ_PREDICT(PREPARE_INPUT.out.input_file)
    BOLTZ_SUMMARISE_RESULTS(BOLTZ_PREDICT.out.results_dir)
}
