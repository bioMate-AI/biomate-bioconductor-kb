#!/usr/bin/env nextflow
/*
 * biomni_physiology_analyze_endolysosomal_calcium_dynamics
 * Analyze calcium dynamics in endo-lysosomal compartments using ELGA/ELGA1 probe data.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.time_points = null
params.luminescence_values = null

// Processes
process STEP_1__NP_ARRAY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__np_array_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_array
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_ARRAY'
        touch step_1__np_array_output.txt
    """
}

process STEP_2__NP_TRAPEZOID {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_trapezoid_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_trapezoid
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_TRAPEZOID'
        touch step_2__np_trapezoid_output.txt
    """
}

process STEP_3__NP_WHERE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_where_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_where
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_WHERE'
        touch step_3__np_where_output.txt
    """
}

process STEP_4__NP_ARGMAX {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__np_argmax_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_argmax
    # Runs in unified Docker container
    echo 'Running STEP_4__NP_ARGMAX'
        touch step_4__np_argmax_output.txt
    """
}

process STEP_5__NP_STD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_std_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_std
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_STD'
        touch step_5__np_std_output.txt
    """
}

workflow BIOMNI_PHYSIOLOGY_ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS {
    main:
    ch_time_points = Channel.value(params.time_points)
    ch_luminescence_values = Channel.value(params.luminescence_values)

    STEP_1__NP_ARRAY(ch_luminescence_values)
    STEP_2__NP_TRAPEZOID(STEP_1__NP_ARRAY.out.output)
    STEP_3__NP_WHERE(STEP_2__NP_TRAPEZOID.out.output)
    STEP_4__NP_ARGMAX(STEP_3__NP_WHERE.out.output)
    STEP_5__NP_STD(STEP_4__NP_ARGMAX.out.output)

    emit:
    output = STEP_5__NP_STD.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS()
}