#!/usr/bin/env nextflow
/*
 * biomni_immunology_analyze_cfse_cell_proliferation
 * Analyze CFSE-labeled cell samples to quantify cell division and proliferation.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.fcs_file_path = null
params.cfse_channel = 'FL1-A'
params.lymphocyte_gate = null

// Main process
process ANALYZE_CFSE_CELL_PROLIFERATION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_cfse_cell_proliferation_results.json"), emit: results
    path("analyze_cfse_cell_proliferation_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.immunology import analyze_cfse_cell_proliferation

# Run the tool
try:
    result = analyze_cfse_cell_proliferation(
    fcs_file_path="${params.fcs_file_path}",
    cfse_channel="${params.cfse_channel}",
    lymphocyte_gate="${params.lymphocyte_gate}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_cfse_cell_proliferation_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_cfse_cell_proliferation_output.txt", "w") as f:
    f.write("Biomni: Analyze Cfse Cell Proliferation Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_cfse_cell_proliferation completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_IMMUNOLOGY_ANALYZE_CFSE_CELL_PROLIFERATION {
    take:
    // No file inputs

    main:
    ANALYZE_CFSE_CELL_PROLIFERATION()

    emit:
    results = ANALYZE_CFSE_CELL_PROLIFERATION.out.results
    output = ANALYZE_CFSE_CELL_PROLIFERATION.out.output
}

// Entry workflow
workflow {
    if (!params.fcs_file_path) {
        error "Please provide --fcs_file_path parameter"
    }


    BIOMNI_IMMUNOLOGY_ANALYZE_CFSE_CELL_PROLIFERATION()
}
