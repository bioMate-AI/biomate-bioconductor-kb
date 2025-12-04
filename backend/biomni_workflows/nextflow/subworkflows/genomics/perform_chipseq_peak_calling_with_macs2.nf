#!/usr/bin/env nextflow
/*
 * biomni_genomics_perform_chipseq_peak_calling_with_macs2
 * Perform ChIP-seq peak calling using MACS2 to identify genomic regions with significant binding.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.chip_seq_file = null
params.control_file = null

// Processes
process PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2 {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(chip_seq_file)
    path(control_file)

    output:
    path("perform_chipseq_peak_calling_with_macs2_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_perform_chipseq_peak_calling_with_macs2
    # Runs in unified Docker container
    echo 'Running PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2'
        touch perform_chipseq_peak_calling_with_macs2_output.txt
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

workflow BIOMNI_GENOMICS_PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2 {
    main:
    ch_chip_seq_file = Channel.fromPath(params.chip_seq_file)
    ch_control_file = Channel.fromPath(params.control_file)

    PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2(ch_chip_seq_file, ch_control_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2()
}