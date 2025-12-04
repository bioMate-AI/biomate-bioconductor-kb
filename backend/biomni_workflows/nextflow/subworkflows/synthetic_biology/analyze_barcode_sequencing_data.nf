#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_analyze_barcode_sequencing_data
 * Analyze sequencing data to extract, quantify and determine lineage relationships of barcodes.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.input_file = null

// Processes
process ANALYZE_BARCODE_SEQUENCING_DATA {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("analyze_barcode_sequencing_data_output.txt"), emit: output

    script:
    """
    # Tool: biomni_synthetic_biology_analyze_barcode_sequencing_data
    # Runs in unified Docker container
    echo 'Running ANALYZE_BARCODE_SEQUENCING_DATA'
        touch analyze_barcode_sequencing_data_output.txt
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

workflow BIOMNI_SYNTHETIC_BIOLOGY_ANALYZE_BARCODE_SEQUENCING_DATA {
    main:
    ch_input_file = Channel.fromPath(params.input_file)

    ANALYZE_BARCODE_SEQUENCING_DATA(ch_input_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYNTHETIC_BIOLOGY_ANALYZE_BARCODE_SEQUENCING_DATA()
}