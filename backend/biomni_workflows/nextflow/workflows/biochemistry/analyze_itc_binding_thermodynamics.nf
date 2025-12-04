#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_analyze_itc_binding_thermodynamics
 * Analyzes isothermal titration calorimetry (ITC) data to determine binding affinity and thermodynamic parameters.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__PD_READ_CSV {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__pd_read_csv_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_read_csv
    # Runs in unified Docker container
    echo 'Running STEP_1__PD_READ_CSV'
        touch step_1__pd_read_csv_output.txt
    """
}

process STEP_2__NP_ARRAY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_array_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_array
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_ARRAY'
        touch step_2__np_array_output.txt
    """
}

process STEP_3__NP_ZEROS_LIKE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_zeros_like_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_zeros_like
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_ZEROS_LIKE'
        touch step_3__np_zeros_like_output.txt
    """
}

process STEP_4__NP_CUMSUM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__np_cumsum_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_cumsum
    # Runs in unified Docker container
    echo 'Running STEP_4__NP_CUMSUM'
        touch step_4__np_cumsum_output.txt
    """
}

workflow BIOMNI_BIOCHEMISTRY_ANALYZE_ITC_BINDING_THERMODYNAMICS {
    main:

    STEP_1__PD_READ_CSV()
    STEP_2__NP_ARRAY(STEP_1__PD_READ_CSV.out.output)
    STEP_3__NP_ZEROS_LIKE(STEP_2__NP_ARRAY.out.output)
    STEP_4__NP_CUMSUM(STEP_3__NP_ZEROS_LIKE.out.output)

    emit:
    output = STEP_4__NP_CUMSUM.out.output
}

workflow {
    BIOMNI_BIOCHEMISTRY_ANALYZE_ITC_BINDING_THERMODYNAMICS()
}