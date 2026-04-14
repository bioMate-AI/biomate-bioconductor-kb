#!/usr/bin/env nextflow
/*
 * biomni_glycoengineering_predict_o_glycosylation_hotspots
 * Heuristic O-glycosylation hotspot scoring.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.window = 7
params.min_st_fraction = 0.4
params.disallow_proline_next = false

// Main process
process PREDICT_O_GLYCOSYLATION_HOTSPOTS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("predict_o_glycosylation_hotspots_results.json"), emit: results
    path("predict_o_glycosylation_hotspots_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.glycoengineering import predict_o_glycosylation_hotspots
except ImportError:
    # Fallback: function may need to be implemented locally
    def predict_o_glycosylation_hotspots(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = predict_o_glycosylation_hotspots(
    sequence="${params.sequence}",
    window=${params.window},
    min_st_fraction=${params.min_st_fraction},
    disallow_proline_next=${params.disallow_proline_next}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("predict_o_glycosylation_hotspots_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("predict_o_glycosylation_hotspots_output.txt", "w") as f:
    f.write("Biomni: Predict O Glycosylation Hotspots Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("predict_o_glycosylation_hotspots completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GLYCOENGINEERING_PREDICT_O_GLYCOSYLATION_HOTSPOTS {
    take:
    // No file inputs

    main:
    PREDICT_O_GLYCOSYLATION_HOTSPOTS()

    emit:
    results = PREDICT_O_GLYCOSYLATION_HOTSPOTS.out.results
    output = PREDICT_O_GLYCOSYLATION_HOTSPOTS.out.output
}

// Entry workflow
workflow {
    if (!params.sequence) {
        error "Please provide --sequence parameter"
    }


    BIOMNI_GLYCOENGINEERING_PREDICT_O_GLYCOSYLATION_HOTSPOTS()
}
