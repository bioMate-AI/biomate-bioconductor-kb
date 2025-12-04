#!/usr/bin/env nextflow
/*
 * biomni_glycoengineering_predict_o_glycosylation_hotspots
 * Heuristic O-glycosylation hotspot scoring.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process PREDICT_O_GLYCOSYLATION_HOTSPOTS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("predict_o_glycosylation_hotspots_output.txt"), emit: output

    script:
    """
    # Tool: biomni_glycoengineering_predict_o_glycosylation_hotspots
    # Runs in unified Docker container
    echo 'Running PREDICT_O_GLYCOSYLATION_HOTSPOTS'
        touch predict_o_glycosylation_hotspots_output.txt
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

workflow BIOMNI_GLYCOENGINEERING_PREDICT_O_GLYCOSYLATION_HOTSPOTS {
    main:

    PREDICT_O_GLYCOSYLATION_HOTSPOTS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GLYCOENGINEERING_PREDICT_O_GLYCOSYLATION_HOTSPOTS()
}