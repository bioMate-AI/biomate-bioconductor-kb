#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_find_orfs_in_frame
 * Helper function to find ORFs in a specific frame.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process FIND_ORFS_IN_FRAME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("find_orfs_in_frame_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_find_orfs_in_frame
    # Runs in unified Docker container
    echo 'Running FIND_ORFS_IN_FRAME'
        touch find_orfs_in_frame_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_FIND_ORFS_IN_FRAME {
    main:

    FIND_ORFS_IN_FRAME()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_FIND_ORFS_IN_FRAME()
}