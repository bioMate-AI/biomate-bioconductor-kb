#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_mass_action_kinetics
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.reaction = null
params.concentrations = null
params.metabolite_ids = null

// Main process
process MASS_ACTION_KINETICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("mass_action_kinetics_results.json"), emit: results
    path("mass_action_kinetics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.systems_biology import mass_action_kinetics

# Run the tool
try:
    result = mass_action_kinetics(
    reaction="${params.reaction}",
    concentrations="${params.concentrations}",
    metabolite_ids="${params.metabolite_ids}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("mass_action_kinetics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("mass_action_kinetics_output.txt", "w") as f:
    f.write("Biomni: Mass Action Kinetics Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("mass_action_kinetics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYSTEMS_BIOLOGY_MASS_ACTION_KINETICS {
    take:
    // No file inputs

    main:
    MASS_ACTION_KINETICS()

    emit:
    results = MASS_ACTION_KINETICS.out.results
    output = MASS_ACTION_KINETICS.out.output
}

// Entry workflow
workflow {
    if (!params.reaction) {
        error "Please provide --reaction parameter"
    }
    if (!params.concentrations) {
        error "Please provide --concentrations parameter"
    }
    if (!params.metabolite_ids) {
        error "Please provide --metabolite_ids parameter"
    }


    BIOMNI_SYSTEMS_BIOLOGY_MASS_ACTION_KINETICS()
}
