#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_run_diffdock_with_smiles
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.pdb_path = null

// Processes
process RUN_DIFFDOCK_WITH_SMILES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(pdb_path)

    output:
    path("run_diffdock_with_smiles_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pharmacology_run_diffdock_with_smiles
    # Runs in unified Docker container
    echo 'Running RUN_DIFFDOCK_WITH_SMILES'
        touch run_diffdock_with_smiles_output.txt
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

workflow BIOMNI_PHARMACOLOGY_RUN_DIFFDOCK_WITH_SMILES {
    main:
    ch_pdb_path = Channel.fromPath(params.pdb_path)

    RUN_DIFFDOCK_WITH_SMILES(ch_pdb_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_RUN_DIFFDOCK_WITH_SMILES()
}