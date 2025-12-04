#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_analyze_calcium_imaging_data
 * Analyze calcium imaging data to quantify neuronal activity metrics including cell counts, event rates, decay times, and signal-to-noise ratios.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_stack_path = null

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

process STEP_2__FEATURE_PEAK_LOCAL_MAX {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__feature_peak_local_max_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_feature_peak_local_max
    # Runs in unified Docker container
    echo 'Running STEP_2__FEATURE_PEAK_LOCAL_MAX'
        touch step_2__feature_peak_local_max_output.txt
    """
}

process STEP_3__MEASURE_REGIONPROPS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__measure_regionprops_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_measure_regionprops
    # Runs in unified Docker container
    echo 'Running STEP_3__MEASURE_REGIONPROPS'
        touch step_3__measure_regionprops_output.txt
    """
}

process STEP_4__MEASURE_LABEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__measure_label_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_measure_label
    # Runs in unified Docker container
    echo 'Running STEP_4__MEASURE_LABEL'
        touch step_4__measure_label_output.txt
    """
}

process STEP_5__SEGMENTATION_WATERSHED {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__segmentation_watershed_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_segmentation_watershed
    # Runs in unified Docker container
    echo 'Running STEP_5__SEGMENTATION_WATERSHED'
        touch step_5__segmentation_watershed_output.txt
    """
}

workflow BIOMNI_BIOENGINEERING_ANALYZE_CALCIUM_IMAGING_DATA {
    main:
    ch_image_stack_path = Channel.value(params.image_stack_path)

    STEP_1__IO_IMREAD(ch_image_stack_path)
    STEP_2__FEATURE_PEAK_LOCAL_MAX(STEP_1__IO_IMREAD.out.output)
    STEP_3__MEASURE_REGIONPROPS(STEP_2__FEATURE_PEAK_LOCAL_MAX.out.output)
    STEP_4__MEASURE_LABEL(STEP_3__MEASURE_REGIONPROPS.out.output)
    STEP_5__SEGMENTATION_WATERSHED(STEP_4__MEASURE_LABEL.out.output)

    emit:
    output = STEP_5__SEGMENTATION_WATERSHED.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_ANALYZE_CALCIUM_IMAGING_DATA()
}