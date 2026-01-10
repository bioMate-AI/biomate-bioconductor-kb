#!/usr/bin/env nextflow
/*
 * biomni_physiology_analyze_protein_colocalization
 * Analyze colocalization between two fluorescently labeled proteins in microscopy images.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.channel1_path = null
params.channel2_path = null

// Processes
process ANALYZE_PROTEIN_COLOCALIZATION {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(channel1_path)
    path(channel2_path)

    output:
    path("analyze_protein_colocalization_output.txt"), emit: output

    script:
    """
    # Tool: biomni_physiology_analyze_protein_colocalization
    # Runs in unified Docker container
    echo 'Running ANALYZE_PROTEIN_COLOCALIZATION'
        touch analyze_protein_colocalization_output.txt
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

workflow BIOMNI_PHYSIOLOGY_ANALYZE_PROTEIN_COLOCALIZATION {
    main:
    ch_channel1_path = Channel.fromPath(params.channel1_path)
    ch_channel2_path = Channel.fromPath(params.channel2_path)

    ANALYZE_PROTEIN_COLOCALIZATION(ch_channel1_path, ch_channel2_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_ANALYZE_PROTEIN_COLOCALIZATION()
}