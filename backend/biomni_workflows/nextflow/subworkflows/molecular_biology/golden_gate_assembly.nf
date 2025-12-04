#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_golden_gate_assembly
 * Simulate Golden Gate assembly to predict final construct sequences.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process GOLDEN_GATE_ASSEMBLY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("golden_gate_assembly_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_golden_gate_assembly
    # Runs in unified Docker container
    echo 'Running GOLDEN_GATE_ASSEMBLY'
        touch golden_gate_assembly_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_GOLDEN_GATE_ASSEMBLY {
    main:

    GOLDEN_GATE_ASSEMBLY()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_GOLDEN_GATE_ASSEMBLY()
}