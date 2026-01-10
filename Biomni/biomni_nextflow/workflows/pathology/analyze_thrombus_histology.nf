#!/usr/bin/env nextflow
/*
 * biomni_pathology_analyze_thrombus_histology
 * Analyze histological images of thrombus samples stained with H&E to identify and quantify different thrombus components (fresh, cellular lysis, endothelialization, fibroblastic reaction).
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_path = null

// Processes
process STEP_1__CV2_CVTCOLOR {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__cv2_cvtcolor_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_cvtColor
    # Runs in unified Docker container
    echo 'Running STEP_1__CV2_CVTCOLOR'
        touch step_1__cv2_cvtcolor_output.txt
    """
}

process STEP_2__CV2_IMREAD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__cv2_imread_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_imread
    # Runs in unified Docker container
    echo 'Running STEP_2__CV2_IMREAD'
        touch step_2__cv2_imread_output.txt
    """
}

process STEP_3__CV2_IMWRITE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__cv2_imwrite_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_imwrite
    # Runs in unified Docker container
    echo 'Running STEP_3__CV2_IMWRITE'
        touch step_3__cv2_imwrite_output.txt
    """
}

process STEP_4__COLOR_RGB2LAB {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__color_rgb2lab_output.txt"), emit: output

    script:
    """
    # Tool: python_skimage_color_rgb2lab
    # Runs in unified Docker container
    echo 'Running STEP_4__COLOR_RGB2LAB'
        touch step_4__color_rgb2lab_output.txt
    """
}

process STEP_5__NP_ZEROS_LIKE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__np_zeros_like_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_zeros_like
    # Runs in unified Docker container
    echo 'Running STEP_5__NP_ZEROS_LIKE'
        touch step_5__np_zeros_like_output.txt
    """
}

workflow BIOMNI_PATHOLOGY_ANALYZE_THROMBUS_HISTOLOGY {
    main:
    ch_image_path = Channel.value(params.image_path)

    STEP_1__CV2_CVTCOLOR(ch_image_path)
    STEP_2__CV2_IMREAD(STEP_1__CV2_CVTCOLOR.out.output)
    STEP_3__CV2_IMWRITE(STEP_2__CV2_IMREAD.out.output)
    STEP_4__COLOR_RGB2LAB(STEP_3__CV2_IMWRITE.out.output)
    STEP_5__NP_ZEROS_LIKE(STEP_4__COLOR_RGB2LAB.out.output)

    emit:
    output = STEP_5__NP_ZEROS_LIKE.out.output
}

workflow {
    BIOMNI_PATHOLOGY_ANALYZE_THROMBUS_HISTOLOGY()
}