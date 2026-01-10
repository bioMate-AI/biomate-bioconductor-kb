#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_analyze_calcium_imaging_data
 * Analyze calcium imaging data to quantify neuronal activity metrics.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_stack_path = null

// Processes
process ANALYZE_CALCIUM_IMAGING_DATA {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(image_stack_path)

    output:
    path("analyze_calcium_imaging_data_output.txt"), emit: output

    script:
    """
    # Tool: biomni_bioengineering_analyze_calcium_imaging_data
    # Runs in unified Docker container
    echo 'Running ANALYZE_CALCIUM_IMAGING_DATA'
        touch analyze_calcium_imaging_data_output.txt
    """
}

process OUTPUT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("output_output.txt"), emit: output

    script:
    """
    # Tool: cat1
    # Runs in unified Docker container
    echo 'Running OUTPUT'
        touch output_output.txt
    """
}

workflow BIOMNI_BIOENGINEERING_ANALYZE_CALCIUM_IMAGING_DATA {
    main:
    ch_image_stack_path = Channel.fromPath(params.image_stack_path)

    ANALYZE_CALCIUM_IMAGING_DATA(ch_image_stack_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_ANALYZE_CALCIUM_IMAGING_DATA()
}