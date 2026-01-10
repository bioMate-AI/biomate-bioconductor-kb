#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_golden_gate_assembly_protocol
 * Return a customized protocol for Golden Gate assembly based on the number of inserts
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("get_golden_gate_assembly_protocol_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_get_golden_gate_assembly_protocol
    # Runs in unified Docker container
    echo 'Running GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL'
        touch get_golden_gate_assembly_protocol_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL {
    main:

    GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL()
}