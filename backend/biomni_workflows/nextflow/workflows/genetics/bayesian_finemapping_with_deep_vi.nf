#!/usr/bin/env nextflow
/*
 * biomni_genetics_bayesian_finemapping_with_deep_vi
 * Performs Bayesian fine-mapping from GWAS summary statistics using deep variational inference to compute posterior inclusion probabilities and credible sets for putative causal variants.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.gwas_summary_path = null
params.ld_matrix = null

// Processes
process STEP_1__PD_READ_CSV {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

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

process STEP_2__NORM_PPF {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__norm_ppf_output.txt"), emit: output

    script:
    """
    # Tool: python_scipy_norm_ppf
    # Runs in unified Docker container
    echo 'Running STEP_2__NORM_PPF'
        touch step_2__norm_ppf_output.txt
    """
}

process STEP_3__TORCH_FLOATTENSOR {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__torch_floattensor_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_FloatTensor
    # Runs in unified Docker container
    echo 'Running STEP_3__TORCH_FLOATTENSOR'
        touch step_3__torch_floattensor_output.txt
    """
}

workflow BIOMNI_GENETICS_BAYESIAN_FINEMAPPING_WITH_DEEP_VI {
    main:
    ch_gwas_summary_path = Channel.value(params.gwas_summary_path)
    ch_ld_matrix = Channel.value(params.ld_matrix)

    STEP_1__PD_READ_CSV(ch_ld_matrix)
    STEP_2__NORM_PPF(STEP_1__PD_READ_CSV.out.output)
    STEP_3__TORCH_FLOATTENSOR(STEP_2__NORM_PPF.out.output)

    emit:
    output = STEP_3__TORCH_FLOATTENSOR.out.output
}

workflow {
    BIOMNI_GENETICS_BAYESIAN_FINEMAPPING_WITH_DEEP_VI()
}