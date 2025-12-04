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
process ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2 {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(background_image_path)
    path(control_image_path)
    path(sample_image_path)

    output:
    path("analyze_intracellular_calcium_with_rhod2_output.txt"), emit: output

    script:
    """
    # Tool: biomni_pathology_analyze_intracellular_calcium_with_rhod2
    # Runs in unified Docker container
    echo 'Running ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2'
        touch analyze_intracellular_calcium_with_rhod2_output.txt
    """
}

process OUTPUT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("output_output.txt"), emit: output

    script:
    """
    # Tool: cat1
    # Runs in unified Docker container
    echo 'Running OUTPUT'
        touch output_output.txt
    """
}

workflow BIOMNI_PATHOLOGY_ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2 {
    main:
    ch_background_image_path = Channel.fromPath(params.background_image_path)
    ch_control_image_path = Channel.fromPath(params.control_image_path)
    ch_sample_image_path = Channel.fromPath(params.sample_image_path)

    ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2(ch_background_image_path, ch_control_image_path, ch_sample_image_path)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_PATHOLOGY_ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2()
}