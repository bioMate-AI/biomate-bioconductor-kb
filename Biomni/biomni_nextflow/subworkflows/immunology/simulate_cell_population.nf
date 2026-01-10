#!/usr/bin/env nextflow
/*
 * biomni_immunology_simulate_cell_population
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process SIMULATE_CELL_POPULATION {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("simulate_cell_population_output.txt"), emit: output

    script:
    """
    # Tool: biomni_immunology_simulate_cell_population
    # Runs in unified Docker container
    echo 'Running SIMULATE_CELL_POPULATION'
        touch simulate_cell_population_output.txt
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

workflow BIOMNI_IMMUNOLOGY_SIMULATE_CELL_POPULATION {
    main:

    SIMULATE_CELL_POPULATION()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_SIMULATE_CELL_POPULATION()
}