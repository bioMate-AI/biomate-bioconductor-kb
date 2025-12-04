#!/usr/bin/env nextflow
/*
 * biomni_microbiology_enumerate_bacterial_cfu_by_serial_dilution
 * Quantify bacterial concentration (CFU/mL) using serial dilutions and spot plating.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__NP_RANDOM_POISSON {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__np_random_poisson_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_random_poisson
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_RANDOM_POISSON'
        touch step_1__np_random_poisson_output.txt
    """
}

process STEP_2__NP_RANDOM_SEED {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_random_seed_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_random_seed
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_RANDOM_SEED'
        touch step_2__np_random_seed_output.txt
    """
}

process STEP_3__PD_DATAFRAME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__pd_dataframe_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_DataFrame
    # Runs in unified Docker container
    echo 'Running STEP_3__PD_DATAFRAME'
        touch step_3__pd_dataframe_output.txt
    """
}

workflow BIOMNI_MICROBIOLOGY_ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION {
    main:

    STEP_1__NP_RANDOM_POISSON()
    STEP_2__NP_RANDOM_SEED(STEP_1__NP_RANDOM_POISSON.out.output)
    STEP_3__PD_DATAFRAME(STEP_2__NP_RANDOM_SEED.out.output)

    emit:
    output = STEP_3__PD_DATAFRAME.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION()
}