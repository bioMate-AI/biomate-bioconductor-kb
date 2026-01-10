#!/usr/bin/env nextflow
/*
 * biomni_biophysics_predict_protein_disorder_regions
 * Predicts intrinsically disordered regions (IDRs) in a protein sequence using IUPred2A.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.output_file = null

// Processes
process PREDICT_PROTEIN_DISORDER_REGIONS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(output_file)

    output:
    path("predict_protein_disorder_regions_output.txt"), emit: output

    script:
    """
    # Tool: biomni_biophysics_predict_protein_disorder_regions
    # Runs in unified Docker container
    echo 'Running PREDICT_PROTEIN_DISORDER_REGIONS'
        touch predict_protein_disorder_regions_output.txt
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

workflow BIOMNI_BIOPHYSICS_PREDICT_PROTEIN_DISORDER_REGIONS {
    main:
    ch_output_file = Channel.fromPath(params.output_file)

    PREDICT_PROTEIN_DISORDER_REGIONS(ch_output_file)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOPHYSICS_PREDICT_PROTEIN_DISORDER_REGIONS()
}