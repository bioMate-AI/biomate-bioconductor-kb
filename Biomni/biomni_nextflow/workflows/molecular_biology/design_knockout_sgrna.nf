#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_design_knockout_sgrna
 * Design sgRNAs for CRISPR knockout by searching pre-computed sgRNA libraries. Returns optimized guide RNAs for targeting a specific gene.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.gene_name = null
params.data_lake_path = null

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

workflow BIOMNI_MOLECULAR_BIOLOGY_DESIGN_KNOCKOUT_SGRNA {
    main:
    ch_gene_name = Channel.value(params.gene_name)
    ch_data_lake_path = Channel.value(params.data_lake_path)

    STEP_1__PD_READ_CSV(ch_data_lake_path)

    emit:
    output = STEP_1__PD_READ_CSV.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_DESIGN_KNOCKOUT_SGRNA()
}