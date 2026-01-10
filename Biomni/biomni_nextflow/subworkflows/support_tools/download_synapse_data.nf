#!/usr/bin/env nextflow
/*
 * biomni_support_tools_download_synapse_data
 * Download data from Synapse using entity IDs.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process DOWNLOAD_SYNAPSE_DATA {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("download_synapse_data_output.txt"), emit: output

    script:
    """
    # Tool: biomni_support_tools_download_synapse_data
    # Runs in unified Docker container
    echo 'Running DOWNLOAD_SYNAPSE_DATA'
        touch download_synapse_data_output.txt
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

workflow BIOMNI_SUPPORT_TOOLS_DOWNLOAD_SYNAPSE_DATA {
    main:

    DOWNLOAD_SYNAPSE_DATA()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SUPPORT_TOOLS_DOWNLOAD_SYNAPSE_DATA()
}