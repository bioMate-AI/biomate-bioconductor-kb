#!/usr/bin/env nextflow
/*
 * biomni_microbiology_analyze_arsenic_speciation_hplc_icpms
 * Analyzes arsenic speciation in liquid samples using HPLC-ICP-MS technique.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sample_data = null
params.sample_name = 'Unknown Sample'
params.calibration_data = null

// Main process
process ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_arsenic_speciation_hplc_icpms_results.json"), emit: results
    path("analyze_arsenic_speciation_hplc_icpms_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.microbiology import analyze_arsenic_speciation_hplc_icpms

# Run the tool
try:
    result = analyze_arsenic_speciation_hplc_icpms(
    sample_data="${params.sample_data}",
    sample_name="${params.sample_name}",
    calibration_data="${params.calibration_data}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_arsenic_speciation_hplc_icpms_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_arsenic_speciation_hplc_icpms_output.txt", "w") as f:
    f.write("Biomni: Analyze Arsenic Speciation Hplc Icpms Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_arsenic_speciation_hplc_icpms completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS {
    take:
    // No file inputs

    main:
    ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS()

    emit:
    results = ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS.out.results
    output = ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS.out.output
}

// Entry workflow
workflow {
    if (!params.sample_data) {
        error "Please provide --sample_data parameter"
    }


    BIOMNI_MICROBIOLOGY_ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS()
}
