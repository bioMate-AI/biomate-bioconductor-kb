#!/usr/bin/env nextflow
/*
 * biomni_microbiology_analyze_arsenic_speciation_hplc_icpms
 * Analyzes arsenic speciation in liquid samples using HPLC-ICP-MS technique.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.sample_data = null
params.calibration_data = null

// Processes
process ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(sample_data)
    path(calibration_data)

    output:
    path("analyze_arsenic_speciation_hplc_icpms_output.txt"), emit: output

    script:
    """
    # Tool: biomni_microbiology_analyze_arsenic_speciation_hplc_icpms
    # Runs in unified Docker container
    echo 'Running ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS'
        touch analyze_arsenic_speciation_hplc_icpms_output.txt
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

workflow BIOMNI_MICROBIOLOGY_ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS {
    main:
    ch_sample_data = Channel.fromPath(params.sample_data)
    ch_calibration_data = Channel.fromPath(params.calibration_data)

    ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS(ch_sample_data, ch_calibration_data)
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_MICROBIOLOGY_ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS()
}