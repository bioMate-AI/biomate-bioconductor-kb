#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_analyze_enzyme_kinetics_assay
 * Performs in vitro enzyme kinetics assay and analyzes the dose-dependent effects of modulators.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.enzyme_name = null
params.substrate_concentrations = null
params.enzyme_concentration = null

// Processes
process STEP_1__NP_ARRAY {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_1__np_array_output.txt"), emit: output

    script:
    """
    # Tool: python_numpy_np_array
    # Runs in unified Docker container
    echo 'Running STEP_1__NP_ARRAY'
        touch step_1__np_array_output.txt
    """
}

workflow BIOMNI_BIOCHEMISTRY_ANALYZE_ENZYME_KINETICS_ASSAY {
    main:
    ch_enzyme_name = Channel.value(params.enzyme_name)
    ch_substrate_concentrations = Channel.value(params.substrate_concentrations)
    ch_enzyme_concentration = Channel.value(params.enzyme_concentration)

    STEP_1__NP_ARRAY(ch_enzyme_concentration)

    emit:
    output = STEP_1__NP_ARRAY.out.output
}

workflow {
    BIOMNI_BIOCHEMISTRY_ANALYZE_ENZYME_KINETICS_ASSAY()
}