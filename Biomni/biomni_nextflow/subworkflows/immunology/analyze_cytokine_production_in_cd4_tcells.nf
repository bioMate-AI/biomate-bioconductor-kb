#!/usr/bin/env nextflow
/*
 * biomni_immunology_analyze_cytokine_production_in_cd4_tcells
 * Analyze cytokine production (IFN-γ, IL-17) in CD4+ T cells after antigen stimulation.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.fcs_files_dict = null

// Processes
process ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(fcs_files_dict)

    output:
    path("analyze_cytokine_production_in_cd4_tcells_output.txt"), emit: output

    script:
    """
    # Tool: biomni_immunology_analyze_cytokine_production_in_cd4_tcells
    # Runs in unified Docker container
    echo 'Running ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS'
        touch analyze_cytokine_production_in_cd4_tcells_output.txt
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

workflow BIOMNI_IMMUNOLOGY_ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS {
    main:
    ch_fcs_files_dict = Channel.fromPath(params.fcs_files_dict)

    ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS(ch_fcs_files_dict)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_IMMUNOLOGY_ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS()
}