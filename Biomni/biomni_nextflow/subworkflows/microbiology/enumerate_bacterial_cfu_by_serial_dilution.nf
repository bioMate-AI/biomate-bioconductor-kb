#!/usr/bin/env nextflow
/*
 * biomni_microbiology_enumerate_bacterial_cfu_by_serial_dilution
 * Quantify bacterial concentration (CFU/mL) using serial dilutions and spot plating.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.output_file = null

// Processes
process ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(output_file)

    output:
    path("enumerate_bacterial_cfu_by_serial_dilution_output.txt"), emit: output

    script:
    """
    # Tool: biomni_microbiology_enumerate_bacterial_cfu_by_serial_dilution
    # Runs in unified Docker container
    echo 'Running ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION'
        touch enumerate_bacterial_cfu_by_serial_dilution_output.txt
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

workflow BIOMNI_MICROBIOLOGY_ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION {
    main:
    ch_output_file = Channel.fromPath(params.output_file)

    ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION(ch_output_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION()
}