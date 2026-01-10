#!/usr/bin/env nextflow
/*
 * biomni_microbiology_segment_and_analyze_microbial_cells
 * Perform automated cell segmentation and quantify morphological metrics from fluorescence microscopy images.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_path = null

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

process STEP_2__IO_IMSAVE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__io_imsave_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_io_imsave
    # Runs in unified Docker container
    echo 'Running STEP_2__IO_IMSAVE'
        touch step_2__io_imsave_output.txt
    """
}

process STEP_3__MEASURE_REGIONPROPS_TABLE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__measure_regionprops_table_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_measure_regionprops_table
    # Runs in unified Docker container
    echo 'Running STEP_3__MEASURE_REGIONPROPS_TABLE'
        touch step_3__measure_regionprops_table_output.txt
    """
}

process STEP_4__MORPHOLOGY_BINARY_CLOSING {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__morphology_binary_closing_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_morphology_binary_closing
    # Runs in unified Docker container
    echo 'Running STEP_4__MORPHOLOGY_BINARY_CLOSING'
        touch step_4__morphology_binary_closing_output.txt
    """
}

process STEP_5__MEASURE_LABEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__measure_label_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_measure_label
    # Runs in unified Docker container
    echo 'Running STEP_5__MEASURE_LABEL'
        touch step_5__measure_label_output.txt
    """
}

workflow BIOMNI_MICROBIOLOGY_SEGMENT_AND_ANALYZE_MICROBIAL_CELLS {
    main:
    ch_image_path = Channel.value(params.image_path)

    STEP_1__IO_IMREAD(ch_image_path)
    STEP_2__IO_IMSAVE(STEP_1__IO_IMREAD.out.output)
    STEP_3__MEASURE_REGIONPROPS_TABLE(STEP_2__IO_IMSAVE.out.output)
    STEP_4__MORPHOLOGY_BINARY_CLOSING(STEP_3__MEASURE_REGIONPROPS_TABLE.out.output)
    STEP_5__MEASURE_LABEL(STEP_4__MORPHOLOGY_BINARY_CLOSING.out.output)

    emit:
    output = STEP_5__MEASURE_LABEL.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_SEGMENT_AND_ANALYZE_MICROBIAL_CELLS()
}