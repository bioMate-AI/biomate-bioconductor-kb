#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_analyze_circular_dichroism_spectra
 * Analyzes circular dichroism (CD) spectroscopy data to determine secondary structure and thermal stability.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sample_name = null
params.sample_type = null
params.wavelength_data = null
params.cd_signal_data = null
params.temperature_data = null
params.thermal_cd_data = null
params.output_dir = './'

// Main process
process ANALYZE_CIRCULAR_DICHROISM_SPECTRA {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_circular_dichroism_spectra_results.json"), emit: results
    path("analyze_circular_dichroism_spectra_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.biochemistry import analyze_circular_dichroism_spectra

# Run the tool
try:
    result = analyze_circular_dichroism_spectra(
    sample_name="${params.sample_name}",
    sample_type="${params.sample_type}",
    wavelength_data="${params.wavelength_data}",
    cd_signal_data="${params.cd_signal_data}",
    temperature_data="${params.temperature_data}",
    thermal_cd_data="${params.thermal_cd_data}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_circular_dichroism_spectra_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_circular_dichroism_spectra_output.txt", "w") as f:
    f.write("Biomni: Analyze Circular Dichroism Spectra Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_circular_dichroism_spectra completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOCHEMISTRY_ANALYZE_CIRCULAR_DICHROISM_SPECTRA {
    take:
    // No file inputs

    main:
    ANALYZE_CIRCULAR_DICHROISM_SPECTRA()

    emit:
    results = ANALYZE_CIRCULAR_DICHROISM_SPECTRA.out.results
    output = ANALYZE_CIRCULAR_DICHROISM_SPECTRA.out.output
}

// Entry workflow
workflow {
    if (!params.sample_name) {
        error "Please provide --sample_name parameter"
    }
    if (!params.sample_type) {
        error "Please provide --sample_type parameter"
    }
    if (!params.wavelength_data) {
        error "Please provide --wavelength_data parameter"
    }
    if (!params.cd_signal_data) {
        error "Please provide --cd_signal_data parameter"
    }


    BIOMNI_BIOCHEMISTRY_ANALYZE_CIRCULAR_DICHROISM_SPECTRA()
}
