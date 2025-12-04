#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_analyze_cell_senescence_and_apoptosis
 * Analyze flow cytometry data to quantify senescent and apoptotic cell populations.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.fcs_file_path = null

// Processes
process ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(fcs_file_path)

    output:
    path("analyze_cell_senescence_and_apoptosis_output.txt"), emit: output

    script:
    """
    # Tool: biomni_cancer_biology_analyze_cell_senescence_and_apoptosis
    # Runs in unified Docker container
    echo 'Running ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS'
        touch analyze_cell_senescence_and_apoptosis_output.txt
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

workflow BIOMNI_CANCER_BIOLOGY_ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS {
    main:
    ch_fcs_file_path = Channel.fromPath(params.fcs_file_path)

    ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS(ch_fcs_file_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_CANCER_BIOLOGY_ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS()
}