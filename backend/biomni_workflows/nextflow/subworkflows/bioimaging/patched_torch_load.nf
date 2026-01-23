#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_patched_torch_load
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'

// Main process
process PATCHED_TORCH_LOAD {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("patched_torch_load_results.json"), emit: results
    path("patched_torch_load_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioimaging import patched_torch_load

# Run the tool
try:
    result = patched_torch_load(

    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("patched_torch_load_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("patched_torch_load_output.txt", "w") as f:
    f.write("Biomni: Patched Torch Load Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("patched_torch_load completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_PATCHED_TORCH_LOAD {
    take:
    // No file inputs

    main:
    PATCHED_TORCH_LOAD()

    emit:
    results = PATCHED_TORCH_LOAD.out.results
    output = PATCHED_TORCH_LOAD.out.output
}

// Entry workflow
workflow {



    BIOMNI_BIOIMAGING_PATCHED_TORCH_LOAD()
}
