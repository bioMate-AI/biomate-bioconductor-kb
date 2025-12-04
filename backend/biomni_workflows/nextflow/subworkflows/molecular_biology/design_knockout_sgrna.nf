#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_design_knockout_sgrna
 * Design sgRNAs for CRISPR knockout by searching pre-computed sgRNA libraries.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.data_lake_path = null

// Processes
process DESIGN_KNOCKOUT_SGRNA {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(data_lake_path)

    output:
    path("design_knockout_sgrna_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_design_knockout_sgrna
    # Runs in unified Docker container
    echo 'Running DESIGN_KNOCKOUT_SGRNA'
        touch design_knockout_sgrna_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_DESIGN_KNOCKOUT_SGRNA {
    main:
    ch_data_lake_path = Channel.fromPath(params.data_lake_path)

    DESIGN_KNOCKOUT_SGRNA(ch_data_lake_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_DESIGN_KNOCKOUT_SGRNA()
}