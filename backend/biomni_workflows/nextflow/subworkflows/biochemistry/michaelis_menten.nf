#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_michaelis_menten
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.s = null
params.vmax = null
params.km = null

// Main process
process MICHAELIS_MENTEN {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("michaelis_menten_results.json"), emit: results
    path("michaelis_menten_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.biochemistry import michaelis_menten

# Run the tool
try:
    result = michaelis_menten(
    s="${params.s}",
    vmax="${params.vmax}",
    km="${params.km}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("michaelis_menten_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("michaelis_menten_output.txt", "w") as f:
    f.write("Biomni: Michaelis Menten Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("michaelis_menten completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOCHEMISTRY_MICHAELIS_MENTEN {
    take:
    // No file inputs

    main:
    MICHAELIS_MENTEN()

    emit:
    results = MICHAELIS_MENTEN.out.results
    output = MICHAELIS_MENTEN.out.output
}

// Entry workflow
workflow {
    if (!params.s) {
        error "Please provide --s parameter"
    }
    if (!params.vmax) {
        error "Please provide --vmax parameter"
    }
    if (!params.km) {
        error "Please provide --km parameter"
    }


    BIOMNI_BIOCHEMISTRY_MICHAELIS_MENTEN()
}
