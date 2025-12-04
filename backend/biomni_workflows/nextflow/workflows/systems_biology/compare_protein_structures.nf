#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_compare_protein_structures
 * Compares two protein structures to identify structural differences and conformational changes.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.pdb_file1 = null
params.pdb_file2 = null

// Processes
process STEP_1__SELECT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__select_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_Select
    # Runs in unified Docker container
    echo 'Running STEP_1__SELECT'
        touch step_1__select_output.txt
    """
}

process STEP_2__SUPERIMPOSER {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__superimposer_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_Superimposer
    # Runs in unified Docker container
    echo 'Running STEP_2__SUPERIMPOSER'
        touch step_2__superimposer_output.txt
    """
}

process STEP_3__PDBPARSER {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__pdbparser_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_PDBParser
    # Runs in unified Docker container
    echo 'Running STEP_3__PDBPARSER'
        touch step_3__pdbparser_output.txt
    """
}

process STEP_4__PDBIO {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__pdbio_output.txt"), emit: output

    script:
    """
    # Tool: python_bio_PDBIO
    # Runs in unified Docker container
    echo 'Running STEP_4__PDBIO'
        touch step_4__pdbio_output.txt
    """
}

process STEP_5__NP_LINALG_NORM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_linalg_norm_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_linalg_norm
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_LINALG_NORM'
        touch step_5__np_linalg_norm_output.txt
    """
}

workflow BIOMNI_SYSTEMS_BIOLOGY_COMPARE_PROTEIN_STRUCTURES {
    main:
    ch_pdb_file1 = Channel.value(params.pdb_file1)
    ch_pdb_file2 = Channel.value(params.pdb_file2)

    STEP_1__SELECT(ch_pdb_file2)
    STEP_2__SUPERIMPOSER(STEP_1__SELECT.out.output)
    STEP_3__PDBPARSER(STEP_2__SUPERIMPOSER.out.output)
    STEP_4__PDBIO(STEP_3__PDBPARSER.out.output)
    STEP_5__NP_LINALG_NORM(STEP_4__PDBIO.out.output)

    emit:
    output = STEP_5__NP_LINALG_NORM.out.output
}

workflow {
    BIOMNI_SYSTEMS_BIOLOGY_COMPARE_PROTEIN_STRUCTURES()
}