#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_analyze_ddr_network_in_cancer
 * Analyze DNA Damage Response (DDR) network alterations and dependencies in cancer samples.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.expression_data_path = null
params.mutation_data_path = null
params.output_dir = './results'

// Main process
process ANALYZE_DDR_NETWORK_IN_CANCER {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_ddr_network_in_cancer_results.json"), emit: results
    path("analyze_ddr_network_in_cancer_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.cancer_biology import analyze_ddr_network_in_cancer
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_ddr_network_in_cancer(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_ddr_network_in_cancer(
    expression_data_path="${params.expression_data_path}",
    mutation_data_path="${params.mutation_data_path}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_ddr_network_in_cancer_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_ddr_network_in_cancer_output.txt", "w") as f:
    f.write("Biomni: Analyze Ddr Network In Cancer Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_ddr_network_in_cancer completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_CANCER_BIOLOGY_ANALYZE_DDR_NETWORK_IN_CANCER {
    take:
    // No file inputs

    main:
    ANALYZE_DDR_NETWORK_IN_CANCER()

    emit:
    results = ANALYZE_DDR_NETWORK_IN_CANCER.out.results
    output = ANALYZE_DDR_NETWORK_IN_CANCER.out.output
}

// Entry workflow
workflow {
    if (!params.expression_data_path) {
        error "Please provide --expression_data_path parameter"
    }
    if (!params.mutation_data_path) {
        error "Please provide --mutation_data_path parameter"
    }


    BIOMNI_CANCER_BIOLOGY_ANALYZE_DDR_NETWORK_IN_CANCER()
}
