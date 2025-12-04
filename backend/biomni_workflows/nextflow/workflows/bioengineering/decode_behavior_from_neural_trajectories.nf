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
process STEP_1__NP_ZEROS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__np_zeros_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_zeros
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_ZEROS'
        touch step_1__np_zeros_output.txt
    """
}

process STEP_2__NP_SUM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_sum_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_sum
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_SUM'
        touch step_2__np_sum_output.txt
    """
}

process STEP_3__NP_NAN_TO_NUM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_nan_to_num_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_nan_to_num
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_NAN_TO_NUM'
        touch step_3__np_nan_to_num_output.txt
    """
}

process STEP_4__PLT_FIGURE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__plt_figure_output.txt"), emit: output

    script:
    """
    # Tool: python_matplotlib_plt_figure
    # Runs in unified Docker container
    echo 'Running STEP_4__PLT_FIGURE'
        touch step_4__plt_figure_output.txt
    """
}

process STEP_5__PLT_LEGEND {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__plt_legend_output.txt"), emit: output

    script:
    """
    # Tool: python_matplotlib_plt_legend
    # Runs in unified Docker container
    echo 'Running STEP_5__PLT_LEGEND'
        touch step_5__plt_legend_output.txt
    """
}

workflow BIOMNI_BIOENGINEERING_DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES {
    main:
    ch_neural_data = Channel.value(params.neural_data)
    ch_behavioral_data = Channel.value(params.behavioral_data)

    STEP_1__NP_ZEROS(ch_behavioral_data)
    STEP_2__NP_SUM(STEP_1__NP_ZEROS.out.output)
    STEP_3__NP_NAN_TO_NUM(STEP_2__NP_SUM.out.output)
    STEP_4__PLT_FIGURE(STEP_3__NP_NAN_TO_NUM.out.output)
    STEP_5__PLT_LEGEND(STEP_4__PLT_FIGURE.out.output)

    emit:
    output = STEP_5__PLT_LEGEND.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_DECODE_BEHAVIOR_FROM_NEURAL_TRAJECTORIES()
}