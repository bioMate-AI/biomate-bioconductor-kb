#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_design_golden_gate_oligos
 * Design oligos for Golden Gate assembly by identifying backbone overhangs
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process DESIGN_GOLDEN_GATE_OLIGOS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("design_golden_gate_oligos_output.txt"), emit: output

    script:
    """
    # Tool: biomni_molecular_biology_design_golden_gate_oligos
    # Runs in unified Docker container
    echo 'Running DESIGN_GOLDEN_GATE_OLIGOS'
        touch design_golden_gate_oligos_output.txt
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

workflow BIOMNI_MOLECULAR_BIOLOGY_DESIGN_GOLDEN_GATE_OLIGOS {
    main:

    DESIGN_GOLDEN_GATE_OLIGOS()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MOLECULAR_BIOLOGY_DESIGN_GOLDEN_GATE_OLIGOS()
}