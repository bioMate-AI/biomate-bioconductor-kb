#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_analyze_flow_cytometry_immunophenotyping
 * Analyze flow cytometry data to identify and quantify specific cell populations based on surface markers.
 * Generated from Galaxy tool definition
 * Docker: biomate/workflow-tools:latest
 *
 * Default sample data (one-click runnable):
 *   sample_data/flow_cytometry/Accuri_C6_A01_H2O.fcs
 *   Real public FCS3.0 file — BD Accuri C6 flow cytometer, H2O blank, 14 channels
 *   (FSC-A, SSC-A, FL1-4-A/H, Width, Time), 191 events. Sourced from the Galaxy
 *   project's own datatypes test corpus (galaxyproject/galaxy inst
 *   lib/galaxy/datatypes/test/Accuri_C6_A01_H2O.fcs). Galaxy is distributed under
 *   the permissive Academic Free License v3.0 / MIT — its bundled test data is
 *   openly redistributable. Not synthetic.
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default sample data: real public FCS3.0 file (Accuri C6, 14 channels incl. FSC-A/SSC-A,
// 191 events) bundled from Galaxy's own datatypes test data so this workflow is one-click
// runnable with no upload. projectDir-relative so it stages from the launch filesystem on
// AWS Batch (no hardcoded /home or /tmp path). Provenance/license: docs header below.
params.fcs_file_path = "${projectDir}/../../../sample_data/flow_cytometry/Accuri_C6_A01_H2O.fcs"
// Default gating strategy for basic immunophenotyping — scatter gate on channels present in
// the bundled FCS. Format: {"pop_name": [["marker", "operator", threshold], ...]}
params.gating_strategy = '{"lymphocytes": [["FSC-A", "between", [50000, 150000]], ["SSC-A", "between", [10000, 80000]]]}'
params.compensation_matrix = null
params.output_dir = './results'

// Main process
process ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' : 'biomate/workflow-tools:latest'

    input:
    // The FCS file is declared as a staged input so Nextflow copies it into the
    // (S3) work dir and mounts it inside the isolated Batch container. Passing it
    // only as a bare path string would NOT stage it on awsbatch.
    path fcs_file

    output:
    path("analyze_flow_cytometry_immunophenotyping_results.json"), emit: results
    path("analyze_flow_cytometry_immunophenotyping_output.txt"), emit: output

    script:
    """
    # Export parameters as environment variables so structured values (the
    # gating_strategy JSON dict) survive the shell/Python boundary intact.
    # fcs_file is the staged input filename (present in the task work dir).
    export PARAM_FCS_FILE_PATH="${fcs_file}"
    export PARAM_GATING_STRATEGY="${params.gating_strategy?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_COMPENSATION_MATRIX="${params.compensation_matrix?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
import json
import os
from biomni.tool.cell_biology import analyze_flow_cytometry_immunophenotyping

def auto_convert(val):
    # Convert an env-var string to the appropriate Python type.
    if val is None or val == '' or val == 'null':
        return None
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    return val

# Run the tool. gating_strategy must be a dict (per the tool signature); the
# JSON string exported above is parsed back into a dict by auto_convert().
try:
    result = analyze_flow_cytometry_immunophenotyping(
        fcs_file_path=auto_convert(os.environ.get("PARAM_FCS_FILE_PATH", "")),
        gating_strategy=auto_convert(os.environ.get("PARAM_GATING_STRATEGY", "")),
        compensation_matrix=auto_convert(os.environ.get("PARAM_COMPENSATION_MATRIX", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./results")),
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_flow_cytometry_immunophenotyping_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_flow_cytometry_immunophenotyping_output.txt", "w") as f:
    f.write("BioMate: Analyze Flow Cytometry Immunophenotyping Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_flow_cytometry_immunophenotyping completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_CELL_BIOLOGY_ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING {
    take:
    ch_fcs   // channel: path to the FCS file to analyze

    main:
    ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING(ch_fcs)

    emit:
    results = ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING.out.results
    output = ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING.out.output
}

// Entry workflow
workflow {
    if (!params.fcs_file_path) {
        error "Please provide --fcs_file_path parameter"
    }
    if (!params.gating_strategy) {
        error "Please provide --gating_strategy parameter"
    }

    // Build the staged-file channel from the (defaulted) FCS path. checkIfExists
    // fails fast with a clear message if the file is missing on the launch host.
    ch_fcs = Channel.fromPath(params.fcs_file_path, checkIfExists: true)

    BIOMNI_CELL_BIOLOGY_ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING(ch_fcs)
}
