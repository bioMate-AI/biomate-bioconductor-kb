#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_calculate_physicochemical_properties
 * Calculate key physicochemical properties of a drug candidate molecule.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.smiles_string = null

// Processes
process STEP_1__CHEM_MOLFROMSMILES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__chem_molfromsmiles_output.txt"), emit: output

    script:
    """
    # Tool: python_rdkit_Chem_MolFromSmiles
    # Runs in unified Docker container
    echo 'Running STEP_1__CHEM_MOLFROMSMILES'
        touch step_1__chem_molfromsmiles_output.txt
    """
}

process STEP_2__CRIPPEN_MOLMR {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__crippen_molmr_output.txt"), emit: output

    script:
    """
    # Tool: python_rdkit_Crippen_MolMR
    # Runs in unified Docker container
    echo 'Running STEP_2__CRIPPEN_MOLMR'
        touch step_2__crippen_molmr_output.txt
    """
}

process STEP_3__RDMOLSTANDARDIZE_UNCHARGER {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__rdmolstandardize_uncharger_output.txt"), emit: output

    script:
    """
    # Tool: python_rdkit_rdMolStandardize_Uncharger
    # Runs in unified Docker container
    echo 'Running STEP_3__RDMOLSTANDARDIZE_UNCHARGER'
        touch step_3__rdmolstandardize_uncharger_output.txt
    """
}

process STEP_4__DESCRIPTORS_MOLWT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__descriptors_molwt_output.txt"), emit: output

    script:
    """
    # Tool: python_rdkit_Descriptors_MolWt
    # Runs in unified Docker container
    echo 'Running STEP_4__DESCRIPTORS_MOLWT'
        touch step_4__descriptors_molwt_output.txt
    """
}

process STEP_5__DESCRIPTORS_RINGCOUNT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__descriptors_ringcount_output.txt"), emit: output

    script:
    """
    # Tool: python_rdkit_Descriptors_RingCount
    # Runs in unified Docker container
    echo 'Running STEP_5__DESCRIPTORS_RINGCOUNT'
        touch step_5__descriptors_ringcount_output.txt
    """
}

workflow BIOMNI_PHARMACOLOGY_CALCULATE_PHYSICOCHEMICAL_PROPERTIES {
    main:
    ch_smiles_string = Channel.value(params.smiles_string)

    STEP_1__CHEM_MOLFROMSMILES(ch_smiles_string)
    STEP_2__CRIPPEN_MOLMR(STEP_1__CHEM_MOLFROMSMILES.out.output)
    STEP_3__RDMOLSTANDARDIZE_UNCHARGER(STEP_2__CRIPPEN_MOLMR.out.output)
    STEP_4__DESCRIPTORS_MOLWT(STEP_3__RDMOLSTANDARDIZE_UNCHARGER.out.output)
    STEP_5__DESCRIPTORS_RINGCOUNT(STEP_4__DESCRIPTORS_MOLWT.out.output)

    emit:
    output = STEP_5__DESCRIPTORS_RINGCOUNT.out.output
}

workflow {
    BIOMNI_PHARMACOLOGY_CALCULATE_PHYSICOCHEMICAL_PROPERTIES()
}