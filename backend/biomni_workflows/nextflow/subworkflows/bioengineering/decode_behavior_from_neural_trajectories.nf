#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_decode_behavior_from_neural_trajectories
 * Model neural activity trajectories and decode behavioral variables.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.neural_data = null
params.behavioral_data = null
params.n_components = '10'
params.output_dir = './'

// Main process
process DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("decode_behavior_from_neural_trajectories_results.json"), emit: results
    path("decode_behavior_from_neural_trajectories_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioengineering import decode_behavior_from_neural_trajectories

# Run the tool
try:
    result = decode_behavior_from_neural_trajectories(
    neural_data="${params.neural_data}",
    behavioral_data="${params.behavioral_data}",
    n_components="${params.n_components}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("decode_behavior_from_neural_trajectories_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("decode_behavior_from_neural_trajectories_output.txt", "w") as f:
    f.write("Biomni: Decode Behavior From Neural Trajectories Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("decode_behavior_from_neural_trajectories completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOENGINEERING_DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES {
    take:
    // No file inputs

    main:
    DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES()

    emit:
    results = DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES.out.results
    output = DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES.out.output
}

// Entry workflow
workflow {
    if (!params.neural_data) {
        error "Please provide --neural_data parameter"
    }
    if (!params.behavioral_data) {
        error "Please provide --behavioral_data parameter"
    }


    BIOMNI_BIOENGINEERING_DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES()
}
