#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_run_autosite
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.pdb_file = null

// Processes
process RUN_AUTOSITE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(pdb_file)

    output:
    path("run_autosite_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_run_autosite
    # Runs in unified Docker container
    echo 'Running RUN_AUTOSITE'
        touch run_autosite_output.txt
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

workflow BIOMNI_PHARMACOLOGY_RUN_AUTOSITE {
    main:
    ch_pdb_file = Channel.fromPath(params.pdb_file)

    RUN_AUTOSITE(ch_pdb_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_RUN_AUTOSITE()
}