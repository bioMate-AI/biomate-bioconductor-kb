#!/usr/bin/env nextflow
/*
 * biomni_biophysics_analyze_tissue_deformation_flow
 * Quantify tissue deformation and flow dynamics from microscopy image sequence.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.image_sequence = null

// Processes
process STEP_1__CV2_CALCOPTICALFLOWPYRLK {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__cv2_calcopticalflowpyrlk_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_calcOpticalFlowPyrLK
    # Runs in unified Docker container
    echo 'Running STEP_1__CV2_CALCOPTICALFLOWPYRLK'
        touch step_1__cv2_calcopticalflowpyrlk_output.txt
    """
}

process STEP_2__CV2_SOBEL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__cv2_sobel_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_Sobel
    # Runs in unified Docker container
    echo 'Running STEP_2__CV2_SOBEL'
        touch step_2__cv2_sobel_output.txt
    """
}

process STEP_3__CV2_CVTCOLOR {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__cv2_cvtcolor_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_cvtColor
    # Runs in unified Docker container
    echo 'Running STEP_3__CV2_CVTCOLOR'
        touch step_3__cv2_cvtcolor_output.txt
    """
}

process STEP_4__CV2_IMREAD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__cv2_imread_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_imread
    # Runs in unified Docker container
    echo 'Running STEP_4__CV2_IMREAD'
        touch step_4__cv2_imread_output.txt
    """
}

process STEP_5__CV2_IMWRITE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__cv2_imwrite_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_imwrite
    # Runs in unified Docker container
    echo 'Running STEP_5__CV2_IMWRITE'
        touch step_5__cv2_imwrite_output.txt
    """
}

workflow BIOMNI_BIOPHYSICS_ANALYZE_TISSUE_DEFORMATION_FLOW {
    main:
    ch_image_sequence = Channel.value(params.image_sequence)

    STEP_1__CV2_CALCOPTICALFLOWPYRLK(ch_image_sequence)
    STEP_2__CV2_SOBEL(STEP_1__CV2_CALCOPTICALFLOWPYRLK.out.output)
    STEP_3__CV2_CVTCOLOR(STEP_2__CV2_SOBEL.out.output)
    STEP_4__CV2_IMREAD(STEP_3__CV2_CVTCOLOR.out.output)
    STEP_5__CV2_IMWRITE(STEP_4__CV2_IMREAD.out.output)

    emit:
    output = STEP_5__CV2_IMWRITE.out.output
}

workflow {
    BIOMNI_BIOPHYSICS_ANALYZE_TISSUE_DEFORMATION_FLOW()
}