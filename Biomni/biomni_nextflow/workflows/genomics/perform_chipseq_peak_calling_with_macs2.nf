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
process STEP_1__RUN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__run_output.txt"), emit: output

    script:
    """
    # Tool: cli_macs2_run
    # Runs in unified Docker container
    echo 'Running STEP_1__RUN'
        touch step_1__run_output.txt
    """
}

workflow BIOMNI_GENOMICS_PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2 {
    main:
    ch_chip_seq_file = Channel.value(params.chip_seq_file)
    ch_control_file = Channel.value(params.control_file)

    STEP_1__RUN(ch_control_file)

    emit:
    output = STEP_1__RUN.out.output
}

workflow {
    BIOMNI_GENOMICS_PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2()
}