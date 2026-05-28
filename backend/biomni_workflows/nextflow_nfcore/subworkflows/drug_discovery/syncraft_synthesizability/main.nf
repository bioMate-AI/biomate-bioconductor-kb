#!/usr/bin/env nextflow

/**
 * syncraft_synthesizability
 *
 * LLM-guided molecular synthesizability optimization using SynCraft.
 * Uses Chain-of-Thought prompting with Gemini-2.5-Pro to predict atom-level
 * edits (DEL_ATOM, ADD_BOND, DEL_BOND, CHANGE_BOND) that improve synthetic
 * accessibility while preserving target pharmacophore.
 *
 * Inputs:
 *   params.input_smiles  -- SMILES string or file with one SMILES per line
 *   params.max_edits     -- maximum atom-level edits per iteration (default: 5)
 *   params.iterations    -- optimization iterations (default: 3)
 *   params.sa_threshold  -- target SA score threshold (default: 3.0, lower=easier)
 *   params.preserve_scaffold -- preserve core scaffold during edits (default: true)
 *   params.outdir        -- output directory
 */

nextflow.enable.dsl = 2

params.input_smiles       = ''
params.max_edits          = 5
params.iterations         = 3
params.sa_threshold       = 3.0
params.preserve_scaffold  = true
params.outdir             = 'results'
params.publish_dir_mode   = 'copy'

ECR = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/syncraft:latest'

// ── Prepare input SMILES ─────────────────────────────────────────────────────

// [Analysis]
process PREPARE_SMILES {
    tag "prepare"
    label 'process_low'
    container ECR

    input:
    val(smiles_input)

    output:
    path("input_compounds.smi"), emit: smi_file

    script:
    if (smiles_input.endsWith('.smi') || smiles_input.endsWith('.txt')) {
        """
        cp ${smiles_input} input_compounds.smi
        """
    } else {
        """
        echo "${smiles_input}" > input_compounds.smi
        """
    }
}

// ── Run SynCraft synthesizability optimization ────────────────────────────────

// [Retrosynthesis]
process SYNCRAFT_OPTIMIZE {
    tag "syncraft"
    label 'process_medium'
    publishDir "${params.outdir}/optimization", mode: params.publish_dir_mode

    container ECR

    input:
    path(smi_file)

    output:
    path("syncraft_optimized.csv"), emit: optimized
    path("syncraft_edits_log.json"), emit: edits_log

    script:
    def scaffold_flag = params.preserve_scaffold ? '--preserve-scaffold' : ''
    """
    python /opt/syncraft/optimize.py \\
        --input ${smi_file} \\
        --max-edits ${params.max_edits} \\
        --iterations ${params.iterations} \\
        --sa-threshold ${params.sa_threshold} \\
        --output syncraft_optimized.csv \\
        --log syncraft_edits_log.json \\
        ${scaffold_flag}
    """
}

// ── Report ────────────────────────────────────────────────────────────────────

// [Analysis]
process SYNTHESIZABILITY_REPORT {
    tag "report"
    label 'process_low'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    container ECR

    input:
    path(optimized_csv)
    path(edits_log)

    output:
    path("syncraft_report.json"), emit: report

    script:
    """
    python3 - <<'EOF'
import json, csv

with open("${optimized_csv}") as f:
    results = list(csv.DictReader(f))

with open("${edits_log}") as f:
    edits = json.load(f)

improved = [r for r in results if float(r.get('sa_score_after', 10)) < float(r.get('sa_score_before', 10))]

report = {
    "tool": "SynCraft",
    "model": "Gemini-2.5-Pro (Chain-of-Thought)",
    "compounds_processed": len(results),
    "compounds_improved": len(improved),
    "improvement_rate": f"{100*len(improved)/max(len(results),1):.1f}%",
    "sa_threshold": ${params.sa_threshold},
    "iterations": ${params.iterations},
    "results": results[:20],
    "edit_types": edits.get("edit_type_counts", {}),
}
with open("syncraft_report.json", "w") as f:
    json.dump(report, f, indent=2)
print(f"Optimized {len(results)} compounds; {len(improved)} improved SA score")
EOF
    """
}

workflow {
    smiles_ch = Channel.value(params.input_smiles)
    PREPARE_SMILES(smiles_ch)
    SYNCRAFT_OPTIMIZE(PREPARE_SMILES.out.smi_file)
    SYNTHESIZABILITY_REPORT(SYNCRAFT_OPTIMIZE.out.optimized, SYNCRAFT_OPTIMIZE.out.edits_log)
}
