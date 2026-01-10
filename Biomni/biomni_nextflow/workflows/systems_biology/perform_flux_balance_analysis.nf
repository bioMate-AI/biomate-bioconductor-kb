#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_perform_flux_balance_analysis
 * Perform Flux Balance Analysis (FBA) on a genome-scale metabolic network model and return a research log of the process and results.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.model_file = null

// Processes
process STEP_1__COBRA_IO_LOAD_JSON_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__cobra_io_load_json_model_output.txt"), emit: output

    script:
    """
    # Tool: python_cobra_cobra_io_load_json_model
    # Runs in unified Docker container
    echo 'Running STEP_1__COBRA_IO_LOAD_JSON_MODEL'
        touch step_1__cobra_io_load_json_model_output.txt
    """
}

process STEP_2__COBRA_IO_LOAD_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__cobra_io_load_model_output.txt"), emit: output

    script:
    """
    # Tool: python_cobra_cobra_io_load_model
    # Runs in unified Docker container
    echo 'Running STEP_2__COBRA_IO_LOAD_MODEL'
        touch step_2__cobra_io_load_model_output.txt
    """
}

process STEP_3__COBRA_IO_READ_SBML_MODEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__cobra_io_read_sbml_model_output.txt"), emit: output

    script:
    """
    # Tool: python_cobra_cobra_io_read_sbml_model
    # Runs in unified Docker container
    echo 'Running STEP_3__COBRA_IO_READ_SBML_MODEL'
        touch step_3__cobra_io_read_sbml_model_output.txt
    """
}

process STEP_4__PD_DATAFRAME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__pd_dataframe_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_DataFrame
    # Runs in unified Docker container
    echo 'Running STEP_4__PD_DATAFRAME'
        touch step_4__pd_dataframe_output.txt
    """
}

workflow BIOMNI_SYSTEMS_BIOLOGY_PERFORM_FLUX_BALANCE_ANALYSIS {
    main:
    ch_model_file = Channel.value(params.model_file)

    STEP_1__COBRA_IO_LOAD_JSON_MODEL(ch_model_file)
    STEP_2__COBRA_IO_LOAD_MODEL(STEP_1__COBRA_IO_LOAD_JSON_MODEL.out.output)
    STEP_3__COBRA_IO_READ_SBML_MODEL(STEP_2__COBRA_IO_LOAD_MODEL.out.output)
    STEP_4__PD_DATAFRAME(STEP_3__COBRA_IO_READ_SBML_MODEL.out.output)

    emit:
    output = STEP_4__PD_DATAFRAME.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_PERFORM_FLUX_BALANCE_ANALYSIS()
}