#!/usr/bin/env nextflow
/*
 * biomni_microbiology_count_bacterial_colonies
 * Count bacterial colonies from an image of agar plate using computer vision techniques.
 * Converted from Galaxy format
 * Docker: biomate/biotools:arm64
 */

nextflow.enable.dsl = 2

// Parameters
params.image_path = null
params.dilution_factor = 1
params.plate_area_cm2 = 65.0
params.outdir = './results'

// Processes
process COUNT_BACTERIAL_COLONIES {
    tag "${image_path.baseName}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biotools:arm64'

    input:
    path(image_path)

    output:
    path("colony_count_results.json"), emit: results
    path("colony_count_output.txt"), emit: output

    script:
    """
    /opt/conda/envs/biotools/bin/python << 'PYEOF'
import json
import sys
sys.path.insert(0, '/app/Biomni')

from biomni.tool.microbiology import count_bacterial_colonies

# Run the colony counting tool
result = count_bacterial_colonies(
    image_path="${image_path}",
    dilution_factor=${params.dilution_factor},
    plate_area_cm2=${params.plate_area_cm2},
    output_dir="."
)

# Save results
with open("colony_count_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("colony_count_output.txt", "w") as f:
    f.write("Colony Count Results\\n")
    f.write("=" * 50 + "\\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\\n")
    else:
        f.write(str(result))

print("Colony counting completed successfully")
PYEOF
    """
}

process CONCATENATE_OUTPUT {
    tag "${task.process}"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biotools:arm64'

    input:
    path(input_file)

    output:
    path("final_output.txt"), emit: output

    script:
    """
    cat ${input_file} > final_output.txt
    echo "" >> final_output.txt
    echo "Processing completed at: \$(date)" >> final_output.txt
    """
}

workflow BIOMNI_MICROBIOLOGY_COUNT_BACTERIAL_COLONIES {
    take:
    ch_image

    main:
    COUNT_BACTERIAL_COLONIES(ch_image)
    CONCATENATE_OUTPUT(COUNT_BACTERIAL_COLONIES.out.output)

    emit:
    results = COUNT_BACTERIAL_COLONIES.out.results
    output = CONCATENATE_OUTPUT.out.output
}

workflow {
    // Validate input
    if (!params.image_path) {
        error "Please provide --image_path parameter"
    }

    ch_image_path = Channel.fromPath(params.image_path, checkIfExists: true)

    BIOMNI_MICROBIOLOGY_COUNT_BACTERIAL_COLONIES(ch_image_path)
}
