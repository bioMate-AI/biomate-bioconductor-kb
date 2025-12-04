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
process STEP_1__SEQIO_PARSE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__seqio_parse_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_SeqIO_parse
    # Runs in unified Docker container
    echo 'Running STEP_1__SEQIO_PARSE'
        touch step_1__seqio_parse_output.txt
    """
}

workflow BIOMNI_SYNTHETIC_BIOLOGY_ANALYZE_BARCODE_SEQUENCING_DATA {
    main:
    ch_input_file = Channel.value(params.input_file)

    STEP_1__SEQIO_PARSE(ch_input_file)

    emit:
    output = STEP_1__SEQIO_PARSE.out.output
}

workflow {
    BIOMNI_SYNTHETIC_BIOLOGY_ANALYZE_BARCODE_SEQUENCING_DATA()
}