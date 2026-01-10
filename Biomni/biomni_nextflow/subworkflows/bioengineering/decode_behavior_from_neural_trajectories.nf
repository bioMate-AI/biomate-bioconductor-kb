#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_decode_behavior_from_neural_trajectories
 * Model neural activity trajectories and decode behavioral variables.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.neural_data = null
params.behavioral_data = null

// Processes
process DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(neural_data)
    path(behavioral_data)

    output:
    path("decode_behavior_from_neural_trajectories_output.txt"), emit: output

    script:
    """
    # Tool: biomni_bioengineering_decode_behavior_from_neural_trajectories
    # Runs in unified Docker container
    echo 'Running DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES'
        touch decode_behavior_from_neural_trajectories_output.txt
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

workflow BIOMNI_BIOENGINEERING_DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES {
    main:
    ch_neural_data = Channel.fromPath(params.neural_data)
    ch_behavioral_data = Channel.fromPath(params.behavioral_data)

    DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES(ch_neural_data, ch_behavioral_data)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES()
}