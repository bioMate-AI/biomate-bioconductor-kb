#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_perform_gene_expression_nmf_analysis
 * Performs Non-negative Matrix Factorization (NMF) on gene expression data to extract metagenes and their associated sample weights for tumor subtype identification.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.expression_data_path = null

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

process STEP_2__PD_READ_CSV {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__pd_read_csv_output.txt"), emit: output

    script:
    """
    # Tool: python_pandas_pd_read_csv
    # Runs in unified Docker container
    echo 'Running STEP_2__PD_READ_CSV'
        touch step_2__pd_read_csv_output.txt
    """
}

process STEP_3__NP_ABS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_abs_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_abs
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_ABS'
        touch step_3__np_abs_output.txt
    """
}

process STEP_4__NP_SUM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__np_sum_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_sum
    # Runs in unified Docker container
    echo 'Running STEP_4__NP_SUM'
        touch step_4__np_sum_output.txt
    """
}

process STEP_5__NP_ANY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_any_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_any
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_ANY'
        touch step_5__np_any_output.txt
    """
}

workflow BIOMNI_CANCER_BIOLOGY_PERFORM_GENE_EXPRESSION_NMF_ANALYSIS {
    main:
    ch_expression_data_path = Channel.value(params.expression_data_path)

    STEP_1__PD_DATAFRAME(ch_expression_data_path)
    STEP_2__PD_READ_CSV(STEP_1__PD_DATAFRAME.out.output)
    STEP_3__NP_ABS(STEP_2__PD_READ_CSV.out.output)
    STEP_4__NP_SUM(STEP_3__NP_ABS.out.output)
    STEP_5__NP_ANY(STEP_4__NP_SUM.out.output)

    emit:
    output = STEP_5__NP_ANY.out.output
}

workflow {
    BIOMNI_CANCER_BIOLOGY_PERFORM_GENE_EXPRESSION_NMF_ANALYSIS()
}