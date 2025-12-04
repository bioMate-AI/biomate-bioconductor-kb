#!/usr/bin/env nextflow
/*
 * biomni_genetics_analyze_protein_phylogeny
 * Perform phylogenetic analysis on a set of protein sequences. This function aligns sequences, constructs a phylogenetic tree, and visualizes evolutionary relationships.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.fasta_sequences = null

// Processes
process STEP_1__PHYLO_WRITE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__phylo_write_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_Phylo_write
    # Runs in unified Docker container
    echo 'Running STEP_1__PHYLO_WRITE'
        touch step_1__phylo_write_output.txt
    """
}

process STEP_2__MUSCLECOMMANDLINE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__musclecommandline_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_MuscleCommandline
    # Runs in unified Docker container
    echo 'Running STEP_2__MUSCLECOMMANDLINE'
        touch step_2__musclecommandline_output.txt
    """
}

process STEP_3__SEQIO_PARSE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__seqio_parse_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_SeqIO_parse
    # Runs in unified Docker container
    echo 'Running STEP_3__SEQIO_PARSE'
        touch step_3__seqio_parse_output.txt
    """
}

process STEP_4__PAIRWISE2_ALIGN_GLOBALXX {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__pairwise2_align_globalxx_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_pairwise2_align_globalxx
    # Runs in unified Docker container
    echo 'Running STEP_4__PAIRWISE2_ALIGN_GLOBALXX'
        touch step_4__pairwise2_align_globalxx_output.txt
    """
}

process STEP_5__ALIGNIO_READ {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__alignio_read_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_AlignIO_read
    # Runs in unified Docker container
    echo 'Running STEP_5__ALIGNIO_READ'
        touch step_5__alignio_read_output.txt
    """
}

workflow BIOMNI_GENETICS_ANALYZE_PROTEIN_PHYLOGENY {
    main:
    ch_fasta_sequences = Channel.value(params.fasta_sequences)

    STEP_1__PHYLO_WRITE(ch_fasta_sequences)
    STEP_2__MUSCLECOMMANDLINE(STEP_1__PHYLO_WRITE.out.output)
    STEP_3__SEQIO_PARSE(STEP_2__MUSCLECOMMANDLINE.out.output)
    STEP_4__PAIRWISE2_ALIGN_GLOBALXX(STEP_3__SEQIO_PARSE.out.output)
    STEP_5__ALIGNIO_READ(STEP_4__PAIRWISE2_ALIGN_GLOBALXX.out.output)

    emit:
    output = STEP_5__ALIGNIO_READ.out.output
}

workflow {
    BIOMNI_GENETICS_ANALYZE_PROTEIN_PHYLOGENY()
}