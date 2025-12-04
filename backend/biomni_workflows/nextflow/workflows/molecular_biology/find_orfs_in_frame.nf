#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_find_orfs_in_frame
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__SEQ {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__seq_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_Seq
    # Runs in unified Docker container
    echo 'Running STEP_1__SEQ'
        touch step_1__seq_output.txt
    """
}

workflow BIOMNI_MOLECULAR_BIOLOGY_FIND_ORFS_IN_FRAME {
    main:

    STEP_1__SEQ()

    emit:
    output = STEP_1__SEQ.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_FIND_ORFS_IN_FRAME()
}