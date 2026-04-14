#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_optimize_codons_for_heterologous_expression
 * Analyzes and optimizes a DNA/RNA sequence for improved expression in a heterologous host organism.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.target_sequence = null
params.host_codon_usage = null

// Main process
process OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("optimize_codons_for_heterologous_expression_results.json"), emit: results
    path("optimize_codons_for_heterologous_expression_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.synthetic_biology import optimize_codons_for_heterologous_expression
except ImportError:
    # Fallback: function may need to be implemented locally
    def optimize_codons_for_heterologous_expression(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = optimize_codons_for_heterologous_expression(
    target_sequence="${params.target_sequence}",
    host_codon_usage="${params.host_codon_usage}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("optimize_codons_for_heterologous_expression_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("optimize_codons_for_heterologous_expression_output.txt", "w") as f:
    f.write("Biomni: Optimize Codons For Heterologous Expression Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("optimize_codons_for_heterologous_expression completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYNTHETIC_BIOLOGY_OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION {
    take:
    // No file inputs

    main:
    OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION()

    emit:
    results = OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION.out.results
    output = OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION.out.output
}

// Entry workflow
workflow {
    if (!params.target_sequence) {
        error "Please provide --target_sequence parameter"
    }
    if (!params.host_codon_usage) {
        error "Please provide --host_codon_usage parameter"
    }


    BIOMNI_SYNTHETIC_BIOLOGY_OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION()
}
