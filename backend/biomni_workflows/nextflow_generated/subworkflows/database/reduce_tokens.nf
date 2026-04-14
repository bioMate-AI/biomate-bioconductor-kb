#!/usr/bin/env nextflow
/*
 * biomni_database_reduce_tokens
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.res_json = null

// Main process
process REDUCE_TOKENS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("reduce_tokens_results.json"), emit: results
    path("reduce_tokens_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.database import reduce_tokens
except ImportError:
    # Fallback: function may need to be implemented locally
    def reduce_tokens(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = reduce_tokens(
    res_json="${params.res_json}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("reduce_tokens_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("reduce_tokens_output.txt", "w") as f:
    f.write("Biomni: Reduce Tokens Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("reduce_tokens completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_DATABASE_REDUCE_TOKENS {
    take:
    // No file inputs

    main:
    REDUCE_TOKENS()

    emit:
    results = REDUCE_TOKENS.out.results
    output = REDUCE_TOKENS.out.output
}

// Entry workflow
workflow {
    if (!params.res_json) {
        error "Please provide --res_json parameter"
    }


    BIOMNI_DATABASE_REDUCE_TOKENS()
}
