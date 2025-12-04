#!/usr/bin/env nextflow
/*
 * biomni_pathology_quantify_corneal_nerve_fibers
 * Quantify the volume/density of immunofluorescence-labeled corneal nerve fibers.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_path = null

// Processes
process QUANTIFY_CORNEAL_NERVE_FIBERS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(image_path)

    output:
    path("quantify_corneal_nerve_fibers_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pathology_quantify_corneal_nerve_fibers
    # Runs in unified Docker container
    echo 'Running QUANTIFY_CORNEAL_NERVE_FIBERS'
        touch quantify_corneal_nerve_fibers_output.txt
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

workflow BIOMNI_PATHOLOGY_QUANTIFY_CORNEAL_NERVE_FIBERS {
    main:
    ch_image_path = Channel.fromPath(params.image_path)

    QUANTIFY_CORNEAL_NERVE_FIBERS(ch_image_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PATHOLOGY_QUANTIFY_CORNEAL_NERVE_FIBERS()
}