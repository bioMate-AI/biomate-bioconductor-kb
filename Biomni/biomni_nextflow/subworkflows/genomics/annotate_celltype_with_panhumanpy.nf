#!/usr/bin/env nextflow
/*
 * biomni_genomics_annotate_celltype_with_panhumanpy
 * Perform hierarchical cell type annotation using panhumanpy and Azimuth Neural Network.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.adata_path = null

// Processes
process ANNOTATE_CELLTYPE_WITH_PANHUMANPY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(adata_path)

    output:
    path("annotate_celltype_with_panhumanpy_output.txt"), emit: output

    script:
    """
    # Tool: biomni_genomics_annotate_celltype_with_panhumanpy
    # Runs in unified Docker container
    echo 'Running ANNOTATE_CELLTYPE_WITH_PANHUMANPY'
        touch annotate_celltype_with_panhumanpy_output.txt
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

workflow BIOMNI_GENOMICS_ANNOTATE_CELLTYPE_WITH_PANHUMANPY {
    main:
    ch_adata_path = Channel.fromPath(params.adata_path)

    ANNOTATE_CELLTYPE_WITH_PANHUMANPY(ch_adata_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_GENOMICS_ANNOTATE_CELLTYPE_WITH_PANHUMANPY()
}