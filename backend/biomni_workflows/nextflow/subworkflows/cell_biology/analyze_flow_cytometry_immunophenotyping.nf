#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_analyze_flow_cytometry_immunophenotyping
 * Analyze flow cytometry data to identify and quantify specific cell populations based on surface markers.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.fcs_file_path = null

// Processes
process ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(fcs_file_path)

    output:
    path("analyze_flow_cytometry_immunophenotyping_output.txt"), emit: output

    script:
    """
    # Tool: biomni_cell_biology_analyze_flow_cytometry_immunophenotyping
    # Runs in unified Docker container
    echo 'Running ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING'
        touch analyze_flow_cytometry_immunophenotyping_output.txt
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

workflow BIOMNI_CELL_BIOLOGY_ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING {
    main:
    ch_fcs_file_path = Channel.fromPath(params.fcs_file_path)

    ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING(ch_fcs_file_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_CELL_BIOLOGY_ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING()
}