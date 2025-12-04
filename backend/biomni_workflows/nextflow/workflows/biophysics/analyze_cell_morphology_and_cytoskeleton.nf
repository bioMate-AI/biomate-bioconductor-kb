#!/usr/bin/env nextflow
/*
 * biomni_biophysics_analyze_cell_morphology_and_cytoskeleton
 * Quantifies cell morphology and cytoskeletal organization from fluorescence microscopy images.
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

process STEP_2__MORPHOLOGY_REMOVE_SMALL_HOLES {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__morphology_remove_small_holes_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_morphology_remove_small_holes
    # Runs in unified Docker container
    echo 'Running STEP_2__MORPHOLOGY_REMOVE_SMALL_HOLES'
        touch step_2__morphology_remove_small_holes_output.txt
    """
}

process STEP_3__RGB2GRAY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__rgb2gray_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_rgb2gray
    # Runs in unified Docker container
    echo 'Running STEP_3__RGB2GRAY'
        touch step_3__rgb2gray_output.txt
    """
}

process STEP_4__MEASURE_REGIONPROPS_TABLE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__measure_regionprops_table_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_measure_regionprops_table
    # Runs in unified Docker container
    echo 'Running STEP_4__MEASURE_REGIONPROPS_TABLE'
        touch step_4__measure_regionprops_table_output.txt
    """
}

process STEP_5__IO_IMSAVE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__io_imsave_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_io_imsave
    # Runs in unified Docker container
    echo 'Running STEP_5__IO_IMSAVE'
        touch step_5__io_imsave_output.txt
    """
}

workflow BIOMNI_BIOPHYSICS_ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON {
    main:
    ch_image_path = Channel.value(params.image_path)

    STEP_1__IO_IMREAD(ch_image_path)
    STEP_2__MORPHOLOGY_REMOVE_SMALL_HOLES(STEP_1__IO_IMREAD.out.output)
    STEP_3__RGB2GRAY(STEP_2__MORPHOLOGY_REMOVE_SMALL_HOLES.out.output)
    STEP_4__MEASURE_REGIONPROPS_TABLE(STEP_3__RGB2GRAY.out.output)
    STEP_5__IO_IMSAVE(STEP_4__MEASURE_REGIONPROPS_TABLE.out.output)

    emit:
    output = STEP_5__IO_IMSAVE.out.output
}

workflow {
    BIOMNI_BIOPHYSICS_ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON()
}