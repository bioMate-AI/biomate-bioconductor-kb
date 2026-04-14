#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_simulate_gene_circuit_with_growth_feedback
 * Simulate gene regulatory circuit dynamics with growth feedback.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.circuit_topology = null
params.kinetic_params = null
params.growth_params = null
params.simulation_time = '100'
params.time_points = '1000'

// Main process
process SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("simulate_gene_circuit_with_growth_feedback_results.json"), emit: results
    path("simulate_gene_circuit_with_growth_feedback_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.synthetic_biology import simulate_gene_circuit_with_growth_feedback

# Run the tool
try:
    result = simulate_gene_circuit_with_growth_feedback(
    circuit_topology="${params.circuit_topology}",
    kinetic_params="${params.kinetic_params}",
    growth_params="${params.growth_params}",
    simulation_time="${params.simulation_time}",
    time_points="${params.time_points}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("simulate_gene_circuit_with_growth_feedback_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("simulate_gene_circuit_with_growth_feedback_output.txt", "w") as f:
    f.write("Biomni: Simulate Gene Circuit With Growth Feedback Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("simulate_gene_circuit_with_growth_feedback completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYNTHETIC_BIOLOGY_SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK {
    take:
    // No file inputs

    main:
    SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK()

    emit:
    results = SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK.out.results
    output = SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK.out.output
}

// Entry workflow
workflow {
    if (!params.circuit_topology) {
        error "Please provide --circuit_topology parameter"
    }
    if (!params.kinetic_params) {
        error "Please provide --kinetic_params parameter"
    }
    if (!params.growth_params) {
        error "Please provide --growth_params parameter"
    }


    BIOMNI_SYNTHETIC_BIOLOGY_SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK()
}
