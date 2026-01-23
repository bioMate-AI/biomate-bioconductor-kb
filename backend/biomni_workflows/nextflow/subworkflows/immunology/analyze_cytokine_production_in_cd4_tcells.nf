#!/usr/bin/env nextflow
/*
 * biomni_immunology_analyze_cytokine_production_in_cd4_tcells
 * Analyze cytokine production (IFN-γ, IL-17) in CD4+ T cells after antigen stimulation.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.fcs_files_dict = null
params.output_dir = './results'

// Main process
process ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_cytokine_production_in_cd4_tcells_results.json"), emit: results
    path("analyze_cytokine_production_in_cd4_tcells_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.immunology import analyze_cytokine_production_in_cd4_tcells

# Run the tool
try:
    result = analyze_cytokine_production_in_cd4_tcells(
    fcs_files_dict="${params.fcs_files_dict}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_cytokine_production_in_cd4_tcells_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_cytokine_production_in_cd4_tcells_output.txt", "w") as f:
    f.write("Biomni: Analyze Cytokine Production In Cd4 Tcells Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_cytokine_production_in_cd4_tcells completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_IMMUNOLOGY_ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS {
    take:
    // No file inputs

    main:
    ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS()

    emit:
    results = ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS.out.results
    output = ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS.out.output
}

// Entry workflow
workflow {
    if (!params.fcs_files_dict) {
        error "Please provide --fcs_files_dict parameter"
    }


    BIOMNI_IMMUNOLOGY_ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS()
}
