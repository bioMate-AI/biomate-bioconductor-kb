#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_compare_protein_structures
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.pdb_file1 = null
params.pdb_file2 = null

// Processes
process COMPARE_PROTEIN_STRUCTURES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(pdb_file1)
    path(pdb_file2)

    output:
    path("compare_protein_structures_output.txt"), emit: output

    script:
    """
    # Tool: biomni_systems_biology_compare_protein_structures
    # Runs in unified Docker container
    echo 'Running COMPARE_PROTEIN_STRUCTURES'
        touch compare_protein_structures_output.txt
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

workflow BIOMNI_SYSTEMS_BIOLOGY_COMPARE_PROTEIN_STRUCTURES {
    main:
    ch_pdb_file1 = Channel.fromPath(params.pdb_file1)
    ch_pdb_file2 = Channel.fromPath(params.pdb_file2)

    COMPARE_PROTEIN_STRUCTURES(ch_pdb_file1, ch_pdb_file2)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_COMPARE_PROTEIN_STRUCTURES()
}