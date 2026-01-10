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

// Processes
process ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(bacterial_genome_file)

    output:
    path("engineer_bacterial_genome_for_therapeutic_delivery_output.txt"), emit: output

    script:
    """
    # Tool: biomni_synthetic_biology_engineer_bacterial_genome_for_therapeutic_delivery
    # Runs in unified Docker container
    echo 'Running ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY'
        touch engineer_bacterial_genome_for_therapeutic_delivery_output.txt
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

workflow BIOMNI_SYNTHETIC_BIOLOGY_ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY {
    main:
    ch_bacterial_genome_file = Channel.fromPath(params.bacterial_genome_file)

    ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY(ch_bacterial_genome_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYNTHETIC_BIOLOGY_ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY()
}