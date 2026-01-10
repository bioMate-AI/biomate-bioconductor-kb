#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_analyze_mitochondrial_morphology_and_potential
 * Quantifies metrics of mitochondrial morphology and membrane potential from fluorescence microscopy images.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.morphology_image_path = null
params.potential_image_path = null

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

process STEP_3__UTIL_IMG_AS_FLOAT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__util_img_as_float_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_util_img_as_float
    # Runs in unified Docker container
    echo 'Running STEP_3__UTIL_IMG_AS_FLOAT'
        touch step_3__util_img_as_float_output.txt
    """
}

process STEP_4__MORPHOLOGY_SKELETONIZE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__morphology_skeletonize_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_morphology_skeletonize
    # Runs in unified Docker container
    echo 'Running STEP_4__MORPHOLOGY_SKELETONIZE'
        touch step_4__morphology_skeletonize_output.txt
    """
}

process STEP_5__UTIL_IMG_AS_UBYTE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__util_img_as_ubyte_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_util_img_as_ubyte
    # Runs in unified Docker container
    echo 'Running STEP_5__UTIL_IMG_AS_UBYTE'
        touch step_5__util_img_as_ubyte_output.txt
    """
}

workflow BIOMNI_CELL_BIOLOGY_ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL {
    main:
    ch_morphology_image_path = Channel.value(params.morphology_image_path)
    ch_potential_image_path = Channel.value(params.potential_image_path)

    STEP_1__IO_IMREAD(ch_potential_image_path)
    STEP_2__IO_IMSAVE(STEP_1__IO_IMREAD.out.output)
    STEP_3__UTIL_IMG_AS_FLOAT(STEP_2__IO_IMSAVE.out.output)
    STEP_4__MORPHOLOGY_SKELETONIZE(STEP_3__UTIL_IMG_AS_FLOAT.out.output)
    STEP_5__UTIL_IMG_AS_UBYTE(STEP_4__MORPHOLOGY_SKELETONIZE.out.output)

    emit:
    output = STEP_5__UTIL_IMG_AS_UBYTE.out.output
}

workflow {
    BIOMNI_CELL_BIOLOGY_ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL()
}