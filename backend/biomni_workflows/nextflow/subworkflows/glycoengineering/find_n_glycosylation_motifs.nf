#!/usr/bin/env nextflow
/*
 * biomni_glycoengineering_find_n_glycosylation_motifs
 * Scan a protein sequence for N-linked glycosylation sequons (N-X-[S/T]).
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process FIND_N_GLYCOSYLATION_MOTIFS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("find_n_glycosylation_motifs_output.txt"), emit: output

    script:
    """
    # Tool: biomni_glycoengineering_find_n_glycosylation_motifs
    # Runs in unified Docker container
    echo 'Running FIND_N_GLYCOSYLATION_MOTIFS'
        touch find_n_glycosylation_motifs_output.txt
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

workflow BIOMNI_GLYCOENGINEERING_FIND_N_GLYCOSYLATION_MOTIFS {
    main:

    FIND_N_GLYCOSYLATION_MOTIFS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GLYCOENGINEERING_FIND_N_GLYCOSYLATION_MOTIFS()
}