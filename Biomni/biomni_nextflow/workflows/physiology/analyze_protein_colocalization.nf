#!/usr/bin/env nextflow
/*
 * biomni_physiology_analyze_protein_colocalization
 * Analyze colocalization between two fluorescently labeled proteins in microscopy images.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.channel1_path = null
params.channel2_path = null

// Processes
process STEP_1__IO_IMREAD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__io_imread_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_io_imread
    # Runs in unified Docker container
    echo 'Running STEP_1__IO_IMREAD'
        touch step_1__io_imread_output.txt
    """
}

process STEP_2__FILTERS_THRESHOLD_YEN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__filters_threshold_yen_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_filters_threshold_yen
    # Runs in unified Docker container
    echo 'Running STEP_2__FILTERS_THRESHOLD_YEN'
        touch step_2__filters_threshold_yen_output.txt
    """
}

process STEP_3__FILTERS_THRESHOLD_OTSU {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__filters_threshold_otsu_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_filters_threshold_otsu
    # Runs in unified Docker container
    echo 'Running STEP_3__FILTERS_THRESHOLD_OTSU'
        touch step_3__filters_threshold_otsu_output.txt
    """
}

process STEP_4__FILTERS_THRESHOLD_LI {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__filters_threshold_li_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_filters_threshold_li
    # Runs in unified Docker container
    echo 'Running STEP_4__FILTERS_THRESHOLD_LI'
        touch step_4__filters_threshold_li_output.txt
    """
}

process STEP_5__EXPOSURE_RESCALE_INTENSITY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__exposure_rescale_intensity_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_exposure_rescale_intensity
    # Runs in unified Docker container
    echo 'Running STEP_5__EXPOSURE_RESCALE_INTENSITY'
        touch step_5__exposure_rescale_intensity_output.txt
    """
}

workflow BIOMNI_PHYSIOLOGY_ANALYZE_PROTEIN_COLOCALIZATION {
    main:
    ch_channel1_path = Channel.value(params.channel1_path)
    ch_channel2_path = Channel.value(params.channel2_path)

    STEP_1__IO_IMREAD(ch_channel2_path)
    STEP_2__FILTERS_THRESHOLD_YEN(STEP_1__IO_IMREAD.out.output)
    STEP_3__FILTERS_THRESHOLD_OTSU(STEP_2__FILTERS_THRESHOLD_YEN.out.output)
    STEP_4__FILTERS_THRESHOLD_LI(STEP_3__FILTERS_THRESHOLD_OTSU.out.output)
    STEP_5__EXPOSURE_RESCALE_INTENSITY(STEP_4__FILTERS_THRESHOLD_LI.out.output)

    emit:
    output = STEP_5__EXPOSURE_RESCALE_INTENSITY.out.output
}

workflow {
    BIOMNI_PHYSIOLOGY_ANALYZE_PROTEIN_COLOCALIZATION()
}