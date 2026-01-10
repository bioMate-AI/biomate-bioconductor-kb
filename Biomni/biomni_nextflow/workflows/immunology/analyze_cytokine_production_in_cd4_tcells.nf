#!/usr/bin/env nextflow
/*
 * biomni_immunology_analyze_cytokine_production_in_cd4_tcells
 * Analyze cytokine production (IFN-γ, IL-17) in CD4+ T cells after antigen stimulation.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.fcs_files_dict = null

// Processes
process STEP_1__PD_DATAFRAME {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__pd_dataframe_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_DataFrame
    # Runs in unified Docker container
    echo 'Running STEP_1__PD_DATAFRAME'
        touch step_1__pd_dataframe_output.txt
    """
}

workflow BIOMNI_IMMUNOLOGY_ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS {
    main:
    ch_fcs_files_dict = Channel.value(params.fcs_files_dict)

    STEP_1__PD_DATAFRAME(ch_fcs_files_dict)

    emit:
    output = STEP_1__PD_DATAFRAME.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS()
}