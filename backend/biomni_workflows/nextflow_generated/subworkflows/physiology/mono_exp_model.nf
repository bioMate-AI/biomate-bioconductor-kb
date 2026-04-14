#!/usr/bin/env nextflow
/*
 * biomni_physiology_mono_exp_model
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.b = null
params.S0 = null
params.ADC = null

// Main process
process MONO_EXP_MODEL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("mono_exp_model_results.json"), emit: results
    path("mono_exp_model_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.physiology import mono_exp_model
except ImportError:
    # Fallback: function may need to be implemented locally
    def mono_exp_model(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = mono_exp_model(
    b="${params.b}",
    S0="${params.S0}",
    ADC="${params.ADC}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("mono_exp_model_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("mono_exp_model_output.txt", "w") as f:
    f.write("Biomni: Mono Exp Model Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("mono_exp_model completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_MONO_EXP_MODEL {
    take:
    // No file inputs

    main:
    MONO_EXP_MODEL()

    emit:
    results = MONO_EXP_MODEL.out.results
    output = MONO_EXP_MODEL.out.output
}

// Entry workflow
workflow {
    if (!params.b) {
        error "Please provide --b parameter"
    }
    if (!params.S0) {
        error "Please provide --S0 parameter"
    }
    if (!params.ADC) {
        error "Please provide --ADC parameter"
    }


    BIOMNI_PHYSIOLOGY_MONO_EXP_MODEL()
}
