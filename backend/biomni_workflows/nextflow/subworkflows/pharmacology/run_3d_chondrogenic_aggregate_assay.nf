#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_run_3d_chondrogenic_aggregate_assay
 * Generates a detailed protocol for performing a 3D chondrogenic aggregate culture assay to evaluate compounds' effects on chondrogenesis.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("run_3d_chondrogenic_aggregate_assay_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_run_3d_chondrogenic_aggregate_assay
    # Runs in unified Docker container
    echo 'Running RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY'
        touch run_3d_chondrogenic_aggregate_assay_output.txt
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

workflow BIOMNI_PHARMACOLOGY_RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY {
    main:

    RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY()
}