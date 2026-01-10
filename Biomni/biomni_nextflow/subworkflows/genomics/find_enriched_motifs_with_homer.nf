#!/usr/bin/env nextflow
/*
 * biomni_genomics_find_enriched_motifs_with_homer
 * Find DNA sequence motifs enriched in genomic regions using the HOMER motif discovery software.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.peak_file = null
params.background_file = null

// Processes
process FIND_ENRICHED_MOTIFS_WITH_HOMER {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(peak_file)
    path(background_file)

    output:
    path("find_enriched_motifs_with_homer_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_find_enriched_motifs_with_homer
    # Runs in unified Docker container
    echo 'Running FIND_ENRICHED_MOTIFS_WITH_HOMER'
        touch find_enriched_motifs_with_homer_output.txt
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

workflow BIOMNI_GENOMICS_FIND_ENRICHED_MOTIFS_WITH_HOMER {
    main:
    ch_peak_file = Channel.fromPath(params.peak_file)
    ch_background_file = Channel.fromPath(params.background_file)

    FIND_ENRICHED_MOTIFS_WITH_HOMER(ch_peak_file, ch_background_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_FIND_ENRICHED_MOTIFS_WITH_HOMER()
}