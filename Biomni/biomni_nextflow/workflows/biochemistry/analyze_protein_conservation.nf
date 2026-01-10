#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_analyze_protein_conservation
 * Perform multiple sequence alignment and phylogenetic analysis to identify conserved protein regions.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.protein_sequences = null

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

process STEP_4__ALIGNIO_READ {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__alignio_read_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_AlignIO_read
    # Runs in unified Docker container
    echo 'Running STEP_4__ALIGNIO_READ'
        touch step_4__alignio_read_output.txt
    """
}

process STEP_5__SEQRECORD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__seqrecord_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_SeqRecord
    # Runs in unified Docker container
    echo 'Running STEP_5__SEQRECORD'
        touch step_5__seqrecord_output.txt
    """
}

workflow BIOMNI_BIOCHEMISTRY_ANALYZE_PROTEIN_CONSERVATION {
    main:
    ch_protein_sequences = Channel.value(params.protein_sequences)

    STEP_1__PHYLO_WRITE(ch_protein_sequences)
    STEP_2__MUSCLECOMMANDLINE(STEP_1__PHYLO_WRITE.out.output)
    STEP_3__SEQIO_PARSE(STEP_2__MUSCLECOMMANDLINE.out.output)
    STEP_4__ALIGNIO_READ(STEP_3__SEQIO_PARSE.out.output)
    STEP_5__SEQRECORD(STEP_4__ALIGNIO_READ.out.output)

    emit:
    output = STEP_5__SEQRECORD.out.output
}

workflow {
    BIOMNI_BIOCHEMISTRY_ANALYZE_PROTEIN_CONSERVATION()
}