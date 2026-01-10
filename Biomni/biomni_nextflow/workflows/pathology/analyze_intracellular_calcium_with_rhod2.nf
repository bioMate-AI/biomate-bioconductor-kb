#!/usr/bin/env nextflow
/*
 * biomni_pathology_analyze_intracellular_calcium_with_rhod2
 * Analyzes intracellular calcium concentration using Rhod-2 fluorescent indicator from microscopy images.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.background_image_path = null
params.control_image_path = null
params.sample_image_path = null

// Processes
process STEP_1__CV2_IMREAD {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__cv2_imread_output.txt"), emit: output

    script:
    """
    # Tool: python_cv2_cv2_imread
    # Runs in unified Docker container
    echo 'Running STEP_1__CV2_IMREAD'
        touch step_1__cv2_imread_output.txt
    """
}

process STEP_2__NP_MAXIMUM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__np_maximum_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_maximum
    # Runs in unified Docker container
    echo 'Running STEP_2__NP_MAXIMUM'
        touch step_2__np_maximum_output.txt
    """
}

process STEP_3__NP_MEAN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__np_mean_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_mean
    # Runs in unified Docker container
    echo 'Running STEP_3__NP_MEAN'
        touch step_3__np_mean_output.txt
    """
}

process STEP_4__PLT_FIGURE {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_4__plt_figure_output.txt"), emit: output

    script:
    """
    # Tool: python_matplotlib_plt_figure
    # Runs in unified Docker container
    echo 'Running STEP_4__PLT_FIGURE'
        touch step_4__plt_figure_output.txt
    """
}

process STEP_5__PLT_COLORBAR {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_5__plt_colorbar_output.txt"), emit: output

    script:
    """
    # Tool: python_matplotlib_plt_colorbar
    # Runs in unified Docker container
    echo 'Running STEP_5__PLT_COLORBAR'
        touch step_5__plt_colorbar_output.txt
    """
}

workflow BIOMNI_PATHOLOGY_ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2 {
    main:
    ch_background_image_path = Channel.value(params.background_image_path)
    ch_control_image_path = Channel.value(params.control_image_path)
    ch_sample_image_path = Channel.value(params.sample_image_path)

    STEP_1__CV2_IMREAD(ch_sample_image_path)
    STEP_2__NP_MAXIMUM(STEP_1__CV2_IMREAD.out.output)
    STEP_3__NP_MEAN(STEP_2__NP_MAXIMUM.out.output)
    STEP_4__PLT_FIGURE(STEP_3__NP_MEAN.out.output)
    STEP_5__PLT_COLORBAR(STEP_4__PLT_FIGURE.out.output)

    emit:
    output = STEP_5__PLT_COLORBAR.out.output
}

workflow {
    BIOMNI_PATHOLOGY_ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2()
}