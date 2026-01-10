#!/usr/bin/env nextflow
/*
 * biomni_genetics_perform_pcr_and_gel_electrophoresis
 * Performs PCR amplification of a target transgene and visualizes results using agarose gel electrophoresis.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process PERFORM_PCR_AND_GEL_ELECTROPHORESIS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("perform_pcr_and_gel_electrophoresis_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genetics_perform_pcr_and_gel_electrophoresis
    # Runs in unified Docker container
    echo 'Running PERFORM_PCR_AND_GEL_ELECTROPHORESIS'
        touch perform_pcr_and_gel_electrophoresis_output.txt
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

workflow BIOMNI_GENETICS_PERFORM_PCR_AND_GEL_ELECTROPHORESIS {
    main:

    PERFORM_PCR_AND_GEL_ELECTROPHORESIS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENETICS_PERFORM_PCR_AND_GEL_ELECTROPHORESIS()
}