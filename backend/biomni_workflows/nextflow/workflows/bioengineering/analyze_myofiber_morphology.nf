#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_analyze_myofiber_morphology
 * Quantifies morphological properties of myofibers in microscopy images of tissue sections.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_path = null

// Processes
process STEP_1__EXPOSURE_EQUALIZE_ADAPTHIST {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__exposure_equalize_adapthist_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_exposure_equalize_adapthist
    # Runs in unified Docker container
    echo 'Running STEP_1__EXPOSURE_EQUALIZE_ADAPTHIST'
        touch step_1__exposure_equalize_adapthist_output.txt
    """
}

process STEP_2__IO_IMREAD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__io_imread_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_io_imread
    # Runs in unified Docker container
    echo 'Running STEP_2__IO_IMREAD'
        touch step_2__io_imread_output.txt
    """
}

process STEP_3__IO_IMSAVE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__io_imsave_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_io_imsave
    # Runs in unified Docker container
    echo 'Running STEP_3__IO_IMSAVE'
        touch step_3__io_imsave_output.txt
    """
}

process STEP_4__MEASURE_REGIONPROPS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__measure_regionprops_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_measure_regionprops
    # Runs in unified Docker container
    echo 'Running STEP_4__MEASURE_REGIONPROPS'
        touch step_4__measure_regionprops_output.txt
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

workflow BIOMNI_BIOENGINEERING_ANALYZE_MYOFIBER_MORPHOLOGY {
    main:
    ch_image_path = Channel.value(params.image_path)

    STEP_1__EXPOSURE_EQUALIZE_ADAPTHIST(ch_image_path)
    STEP_2__IO_IMREAD(STEP_1__EXPOSURE_EQUALIZE_ADAPTHIST.out.output)
    STEP_3__IO_IMSAVE(STEP_2__IO_IMREAD.out.output)
    STEP_4__MEASURE_REGIONPROPS(STEP_3__IO_IMSAVE.out.output)
    STEP_5__MEASURE_LABEL(STEP_4__MEASURE_REGIONPROPS.out.output)

    emit:
    output = STEP_5__MEASURE_LABEL.out.output
}

workflow {
    BIOMNI_BIOENGINEERING_ANALYZE_MYOFIBER_MORPHOLOGY()
}