#!/usr/bin/env nextflow
/*
 * biomni_genetics_perform_pcr_and_gel_electrophoresis
 * Performs PCR amplification of a target transgene and visualizes results using agarose gel electrophoresis.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.genomic_dna = null

// Processes
process STEP_1__SEQIO_READ {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__seqio_read_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_SeqIO_read
    # Runs in unified Docker container
    echo 'Running STEP_1__SEQIO_READ'
        touch step_1__seqio_read_output.txt
    """
}

process STEP_2__SEQ {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__seq_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_Seq
    # Runs in unified Docker container
    echo 'Running STEP_2__SEQ'
        touch step_2__seq_output.txt
    """
}

process STEP_3__PLT_CLOSE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__plt_close_output.txt"), emit: output

    script:
    """
    # Tool: python_matplotlib_plt_close
    # Runs in unified Docker container
    echo 'Running STEP_3__PLT_CLOSE'
        touch step_3__plt_close_output.txt
    """
}

process STEP_4__PLT_SUBPLOTS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__plt_subplots_output.txt"), emit: output

    script:
    """
    # Tool: python_matplotlib_plt_subplots
    # Runs in unified Docker container
    echo 'Running STEP_4__PLT_SUBPLOTS'
        touch step_4__plt_subplots_output.txt
    """
}

process STEP_5__PLT_SAVEFIG {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__plt_savefig_output.txt"), emit: output

    script:
    """
    # Tool: python_matplotlib_plt_savefig
    # Runs in unified Docker container
    echo 'Running STEP_5__PLT_SAVEFIG'
        touch step_5__plt_savefig_output.txt
    """
}

workflow BIOMNI_GENETICS_PERFORM_PCR_AND_GEL_ELECTROPHORESIS {
    main:
    ch_genomic_dna = Channel.value(params.genomic_dna)

    STEP_1__SEQIO_READ(ch_genomic_dna)
    STEP_2__SEQ(STEP_1__SEQIO_READ.out.output)
    STEP_3__PLT_CLOSE(STEP_2__SEQ.out.output)
    STEP_4__PLT_SUBPLOTS(STEP_3__PLT_CLOSE.out.output)
    STEP_5__PLT_SAVEFIG(STEP_4__PLT_SUBPLOTS.out.output)

    emit:
    output = STEP_5__PLT_SAVEFIG.out.output
}

workflow {
    BIOMNI_GENETICS_PERFORM_PCR_AND_GEL_ELECTROPHORESIS()
}