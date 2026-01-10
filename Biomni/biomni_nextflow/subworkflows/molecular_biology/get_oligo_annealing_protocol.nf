#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_oligo_annealing_protocol
 * Return a standard protocol for annealing oligonucleotides without phosphorylation.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_OLIGO_ANNEALING_PROTOCOL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_oligo_annealing_protocol_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_get_oligo_annealing_protocol
    # Runs in unified Docker container
    echo 'Running GET_OLIGO_ANNEALING_PROTOCOL'
        touch get_oligo_annealing_protocol_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_GET_OLIGO_ANNEALING_PROTOCOL {
    main:

    GET_OLIGO_ANNEALING_PROTOCOL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_GET_OLIGO_ANNEALING_PROTOCOL()
}