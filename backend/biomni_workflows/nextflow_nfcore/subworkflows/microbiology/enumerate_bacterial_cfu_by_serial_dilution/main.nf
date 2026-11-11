#!/usr/bin/env nextflow
/*
 * microbiology/enumerate_bacterial_cfu_by_serial_dilution
 * Quantify bacterial concentration (CFU/mL) using serial dilutions and spot plating.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.initial_sample_volume_ml = '1.0'
params.estimated_concentration = '100000000.0'
params.dilution_factor = '10'
params.num_dilutions = '8'
params.spots_per_dilution = '3'
params.output_file = 'cfu_enumeration_results.csv'

process ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' : 'biomate/workflow-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("enumerate_bacterial_cfu_by_serial_dilution_results.json"), emit: results
    tuple val(meta), path("enumerate_bacterial_cfu_by_serial_dilution_output.txt"), emit: output
    path "versions.yml", emit: versions

    // integrity: was an RNG stub fabricating results; honest-fail (no real implementation).
    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_INITIAL_SAMPLE_VOLUME_ML="${params.initial_sample_volume_ml?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ESTIMATED_CONCENTRATION="${params.estimated_concentration?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DILUTION_FACTOR="${params.dilution_factor?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUM_DILUTIONS="${params.num_dilutions?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SPOTS_PER_DILUTION="${params.spots_per_dilution?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILE="${params.output_file?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
import sys
sys.stderr.write("ERROR: enumerate_bacterial_cfu_by_serial_dilution is a wet-lab plate-count procedure with no compute equivalent — CFU/mL can only be derived from real colony counts on actual agar plates (or a real plate/colony-count image). The previous implementation fabricated colony counts with a Poisson random number generator. Refusing to emit fabricated CFU/mL results.\\n")
sys.exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "enumerate_bacterial_cfu_by_serial_dilution"
    END_VERSIONS
    """
}

workflow ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION(ch_input)

    emit:
    results = ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION.out.results
    output = ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION.out.output
    versions = ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION_WORKFLOW(ch_input)

    ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION_WORKFLOW.out.output.view { "Output: $it" }
}
