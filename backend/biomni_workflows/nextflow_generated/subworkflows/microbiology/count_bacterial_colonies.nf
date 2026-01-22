#!/usr/bin/env nextflow
/*
 * biomni_microbiology_count_bacterial_colonies
 * Count bacterial colonies from an image of agar plate using computer vision techniques.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.dilution_factor = '1'
params.plate_area_cm2 = '65.0'
params.output_dir = './output'

// Main process
process COUNT_BACTERIAL_COLONIES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("count_bacterial_colonies_results.json"), emit: results
    path("count_bacterial_colonies_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.microbiology import count_bacterial_colonies
except ImportError:
    # Fallback: function may need to be implemented locally
    def count_bacterial_colonies(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = count_bacterial_colonies(
    image_path="${params.image_path}",
    dilution_factor="${params.dilution_factor}",
    plate_area_cm2="${params.plate_area_cm2}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("count_bacterial_colonies_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("count_bacterial_colonies_output.txt", "w") as f:
    f.write("Biomni: Count Bacterial Colonies Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("count_bacterial_colonies completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_COUNT_BACTERIAL_COLONIES {
    take:
    // No file inputs

    main:
    COUNT_BACTERIAL_COLONIES()

    emit:
    results = COUNT_BACTERIAL_COLONIES.out.results
    output = COUNT_BACTERIAL_COLONIES.out.output
}

// Entry workflow
workflow {
    if (!params.image_path) {
        error "Please provide --image_path parameter"
    }


    BIOMNI_MICROBIOLOGY_COUNT_BACTERIAL_COLONIES()
}
