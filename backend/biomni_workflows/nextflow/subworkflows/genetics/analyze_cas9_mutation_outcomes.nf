#!/usr/bin/env nextflow
/*
 * biomni_genetics_analyze_cas9_mutation_outcomes
 * Analyzes and categorizes mutations induced by Cas9 at target sites.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process ANALYZE_CAS9_MUTATION_OUTCOMES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("analyze_cas9_mutation_outcomes_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genetics_analyze_cas9_mutation_outcomes
    # Runs in unified Docker container
    echo 'Running ANALYZE_CAS9_MUTATION_OUTCOMES'
        touch analyze_cas9_mutation_outcomes_output.txt
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

workflow BIOMNI_GENETICS_ANALYZE_CAS9_MUTATION_OUTCOMES {
    main:

    ANALYZE_CAS9_MUTATION_OUTCOMES()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENETICS_ANALYZE_CAS9_MUTATION_OUTCOMES()
}