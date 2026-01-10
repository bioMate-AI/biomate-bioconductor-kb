#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_docking_autodock_vina
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.receptor_pdb_file = null

// Processes
process DOCKING_AUTODOCK_VINA {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(receptor_pdb_file)

    output:
    path("docking_autodock_vina_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_docking_autodock_vina
    # Runs in unified Docker container
    echo 'Running DOCKING_AUTODOCK_VINA'
        touch docking_autodock_vina_output.txt
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

workflow BIOMNI_PHARMACOLOGY_DOCKING_AUTODOCK_VINA {
    main:
    ch_receptor_pdb_file = Channel.fromPath(params.receptor_pdb_file)

    DOCKING_AUTODOCK_VINA(ch_receptor_pdb_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_DOCKING_AUTODOCK_VINA()
}