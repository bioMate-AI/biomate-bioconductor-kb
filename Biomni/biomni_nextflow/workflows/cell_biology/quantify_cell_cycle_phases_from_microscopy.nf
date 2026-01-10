#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_quantify_cell_cycle_phases_from_microscopy
 * Quantify the percentage of cells in each cell cycle phase using Calcofluor white stained microscopy images.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_paths = null

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

process STEP_2__MEASURE_REGIONPROPS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__measure_regionprops_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_measure_regionprops
    # Runs in unified Docker container
    echo 'Running STEP_2__MEASURE_REGIONPROPS'
        touch step_2__measure_regionprops_output.txt
    """
}

process STEP_3__MEASURE_LABEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__measure_label_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_measure_label
    # Runs in unified Docker container
    echo 'Running STEP_3__MEASURE_LABEL'
        touch step_3__measure_label_output.txt
    """
}

process STEP_4__FILTERS_THRESHOLD_OTSU {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__filters_threshold_otsu_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_filters_threshold_otsu
    # Runs in unified Docker container
    echo 'Running STEP_4__FILTERS_THRESHOLD_OTSU'
        touch step_4__filters_threshold_otsu_output.txt
    """
}

process STEP_5__FILTERS_GAUSSIAN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__filters_gaussian_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_filters_gaussian
    # Runs in unified Docker container
    echo 'Running STEP_5__FILTERS_GAUSSIAN'
        touch step_5__filters_gaussian_output.txt
    """
}

workflow BIOMNI_CELL_BIOLOGY_QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY {
    main:
    ch_image_paths = Channel.value(params.image_paths)

    STEP_1__IO_IMREAD(ch_image_paths)
    STEP_2__MEASURE_REGIONPROPS(STEP_1__IO_IMREAD.out.output)
    STEP_3__MEASURE_LABEL(STEP_2__MEASURE_REGIONPROPS.out.output)
    STEP_4__FILTERS_THRESHOLD_OTSU(STEP_3__MEASURE_LABEL.out.output)
    STEP_5__FILTERS_GAUSSIAN(STEP_4__FILTERS_THRESHOLD_OTSU.out.output)

    emit:
    output = STEP_5__FILTERS_GAUSSIAN.out.output
}

workflow {
    BIOMNI_CELL_BIOLOGY_QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY()
}