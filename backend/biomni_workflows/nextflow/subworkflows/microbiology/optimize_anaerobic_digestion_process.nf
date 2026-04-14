#!/usr/bin/env nextflow
/*
 * biomni_microbiology_optimize_anaerobic_digestion_process
 * Optimize anaerobic digestion process conditions to maximize VFA production or methane yield.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.waste_characteristics = null
params.operational_parameters = null
params.target_output = 'methane_yield'
params.optimization_method = 'rsm'

// Main process
process OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("optimize_anaerobic_digestion_process_results.json"), emit: results
    path("optimize_anaerobic_digestion_process_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.microbiology import optimize_anaerobic_digestion_process

# Run the tool
try:
    result = optimize_anaerobic_digestion_process(
    waste_characteristics="${params.waste_characteristics}",
    operational_parameters="${params.operational_parameters}",
    target_output="${params.target_output}",
    optimization_method="${params.optimization_method}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("optimize_anaerobic_digestion_process_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("optimize_anaerobic_digestion_process_output.txt", "w") as f:
    f.write("Biomni: Optimize Anaerobic Digestion Process Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("optimize_anaerobic_digestion_process completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS {
    take:
    // No file inputs

    main:
    OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS()

    emit:
    results = OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS.out.results
    output = OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS.out.output
}

// Entry workflow
workflow {
    if (!params.waste_characteristics) {
        error "Please provide --waste_characteristics parameter"
    }
    if (!params.operational_parameters) {
        error "Please provide --operational_parameters parameter"
    }


    BIOMNI_MICROBIOLOGY_OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS()
}
