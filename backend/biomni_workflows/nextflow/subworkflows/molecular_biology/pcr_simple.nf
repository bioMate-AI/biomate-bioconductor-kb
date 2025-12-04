#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_pcr_simple
 * Simulate PCR amplification with given primers and sequence. Uses align_sequences internally to find primer binding sites.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.sequence = null
params.forward_primer = null
params.reverse_primer = null
params.circular = null

// Processes
process PCR_PRODUCT_ASSEMBLY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(sequence)
    path(forward_primer)
    path(reverse_primer)
    path(circular)
    path(forward_alignment)
    path(reverse_alignment)

    output:
    path("pcr_product_assembly_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_pcr_simple
    # Runs in unified Docker container
    echo 'Running PCR_PRODUCT_ASSEMBLY'
        touch pcr_product_assembly_output.txt
    """
}

workflow BIOMNI_MOLECULAR_BIOLOGY_PCR_SIMPLE {
    main:
    ch_sequence = Channel.fromPath(params.sequence)
    ch_forward_primer = Channel.fromPath(params.forward_primer)
    ch_reverse_primer = Channel.fromPath(params.reverse_primer)
    ch_circular = Channel.value(params.circular)

    PCR_PRODUCT_ASSEMBLY(ch_sequence, ch_forward_primer, ch_reverse_primer, ch_circular, ALIGN_FORWARD_PRIMER.out.alignments, ALIGN_REVERSE_PRIMER__REV_COMP_.out.alignments)

    emit:
    output = PCR_PRODUCT_ASSEMBLY.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_PCR_SIMPLE()
}