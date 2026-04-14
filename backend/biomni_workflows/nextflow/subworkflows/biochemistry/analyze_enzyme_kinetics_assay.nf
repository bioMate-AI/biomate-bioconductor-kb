#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_analyze_enzyme_kinetics_assay
 * Performs in vitro enzyme kinetics assay and analyzes the dose-dependent effects of modulators.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.enzyme_name = null
params.substrate_concentrations = null
params.enzyme_concentration = null
params.modulators = null
params.time_points = null
params.output_dir = './'

// Main process
process ANALYZE_ENZYME_KINETICS_ASSAY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_enzyme_kinetics_assay_results.json"), emit: results
    path("analyze_enzyme_kinetics_assay_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.biochemistry import analyze_enzyme_kinetics_assay

# Run the tool
try:
    result = analyze_enzyme_kinetics_assay(
    enzyme_name="${params.enzyme_name}",
    substrate_concentrations="${params.substrate_concentrations}",
    enzyme_concentration="${params.enzyme_concentration}",
    modulators="${params.modulators}",
    time_points="${params.time_points}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_enzyme_kinetics_assay_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_enzyme_kinetics_assay_output.txt", "w") as f:
    f.write("Biomni: Analyze Enzyme Kinetics Assay Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_enzyme_kinetics_assay completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOCHEMISTRY_ANALYZE_ENZYME_KINETICS_ASSAY {
    take:
    // No file inputs

    main:
    ANALYZE_ENZYME_KINETICS_ASSAY()

    emit:
    results = ANALYZE_ENZYME_KINETICS_ASSAY.out.results
    output = ANALYZE_ENZYME_KINETICS_ASSAY.out.output
}

// Entry workflow
workflow {
    if (!params.enzyme_name) {
        error "Please provide --enzyme_name parameter"
    }
    if (!params.substrate_concentrations) {
        error "Please provide --substrate_concentrations parameter"
    }
    if (!params.enzyme_concentration) {
        error "Please provide --enzyme_concentration parameter"
    }


    BIOMNI_BIOCHEMISTRY_ANALYZE_ENZYME_KINETICS_ASSAY()
}
