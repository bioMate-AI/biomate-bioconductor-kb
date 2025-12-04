#!/usr/bin/env nextflow
/*
 * biomni_physiology_calculate_brain_adc_map
 * Calculate Apparent Diffusion Coefficient (ADC) map from diffusion-weighted MRI data.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.dwi_file_path = null
params.output_path = null
params.mask_file_path = null

// Processes
process CALCULATE_BRAIN_ADC_MAP {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(dwi_file_path)
    path(output_path)
    path(mask_file_path)

    output:
    path("calculate_brain_adc_map_output.txt"), emit: output

    script:
    """
    # Tool: biomni_physiology_calculate_brain_adc_map
    # Runs in unified Docker container
    echo 'Running CALCULATE_BRAIN_ADC_MAP'
        touch calculate_brain_adc_map_output.txt
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

workflow BIOMNI_PHYSIOLOGY_CALCULATE_BRAIN_ADC_MAP {
    main:
    ch_dwi_file_path = Channel.fromPath(params.dwi_file_path)
    ch_output_path = Channel.fromPath(params.output_path)
    ch_mask_file_path = Channel.fromPath(params.mask_file_path)

    CALCULATE_BRAIN_ADC_MAP(ch_dwi_file_path, ch_output_path, ch_mask_file_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_CALCULATE_BRAIN_ADC_MAP()
}