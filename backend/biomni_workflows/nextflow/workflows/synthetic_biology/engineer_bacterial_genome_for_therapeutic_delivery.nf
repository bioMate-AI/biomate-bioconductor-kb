#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_engineer_bacterial_genome_for_therapeutic_delivery
 * Engineer a bacterial genome by integrating therapeutic genetic parts for therapeutic delivery.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.bacterial_genome_file = null
params.genetic_parts = null

// Processes
process STEP_1__SEQIO_WRITE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__seqio_write_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_SeqIO_write
    # Runs in unified Docker container
    echo 'Running STEP_1__SEQIO_WRITE'
        touch step_1__seqio_write_output.txt
    """
}

process STEP_2__SEQIO_READ {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__seqio_read_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_SeqIO_read
    # Runs in unified Docker container
    echo 'Running STEP_2__SEQIO_READ'
        touch step_2__seqio_read_output.txt
    """
}

process STEP_3__SEQRECORD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__seqrecord_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_SeqRecord
    # Runs in unified Docker container
    echo 'Running STEP_3__SEQRECORD'
        touch step_3__seqrecord_output.txt
    """
}

process STEP_4__SEQFEATURE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__seqfeature_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_SeqFeature
    # Runs in unified Docker container
    echo 'Running STEP_4__SEQFEATURE'
        touch step_4__seqfeature_output.txt
    """
}

process STEP_5__GENOMEDIAGRAM_DIAGRAM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__genomediagram_diagram_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_GenomeDiagram_Diagram
    # Runs in unified Docker container
    echo 'Running STEP_5__GENOMEDIAGRAM_DIAGRAM'
        touch step_5__genomediagram_diagram_output.txt
    """
}

workflow BIOMNI_SYNTHETIC_BIOLOGY_ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY {
    main:
    ch_bacterial_genome_file = Channel.value(params.bacterial_genome_file)
    ch_genetic_parts = Channel.value(params.genetic_parts)

    STEP_1__SEQIO_WRITE(ch_genetic_parts)
    STEP_2__SEQIO_READ(STEP_1__SEQIO_WRITE.out.output)
    STEP_3__SEQRECORD(STEP_2__SEQIO_READ.out.output)
    STEP_4__SEQFEATURE(STEP_3__SEQRECORD.out.output)
    STEP_5__GENOMEDIAGRAM_DIAGRAM(STEP_4__SEQFEATURE.out.output)

    emit:
    output = STEP_5__GENOMEDIAGRAM_DIAGRAM.out.output
}

workflow {
    BIOMNI_SYNTHETIC_BIOLOGY_ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY()
}