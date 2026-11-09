#!/usr/bin/env nextflow
/*
 * immunology/isolate_purify_immune_cells
 * Simulates the isolation and purification of immune cells from tissue samples.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: immune cell isolation parameters
params.tissue_type = 'spleen'
params.target_cell_type = 'macrophages'
params.enzyme_type = 'collagenase'
params.macs_antibody = 'CD11b'
params.digestion_time_min = '45'

process ISOLATE_PURIFY_IMMUNE_CELLS {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' : 'biomate/workflow-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("isolate_purify_immune_cells_results.json"), emit: results
    tuple val(meta), path("isolate_purify_immune_cells_output.txt"), emit: output
    path "versions.yml", emit: versions

    // integrity: was an RNG stub fabricating results; honest-fail (no real implementation).
    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TISSUE_TYPE="${params.tissue_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TARGET_CELL_TYPE="${params.target_cell_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ENZYME_TYPE="${params.enzyme_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MACS_ANTIBODY="${params.macs_antibody?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DIGESTION_TIME_MIN="${params.digestion_time_min?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
import sys
sys.stderr.write("ERROR: isolate_purify_immune_cells is a wet-lab bench procedure with no compute equivalent — reporting cell counts, viability, and purity requires a real cytometer/hemocytometer measurement of an actual isolated cell suspension (flow-cytometry purity, trypan-blue viability). The previous implementation fabricated these numbers via RNG. Refusing to emit fabricated measurements.\\n")
sys.exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "isolate_purify_immune_cells"
    END_VERSIONS
    """
}

workflow ISOLATE_PURIFY_IMMUNE_CELLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ISOLATE_PURIFY_IMMUNE_CELLS(ch_input)

    emit:
    results = ISOLATE_PURIFY_IMMUNE_CELLS.out.results
    output = ISOLATE_PURIFY_IMMUNE_CELLS.out.output
    versions = ISOLATE_PURIFY_IMMUNE_CELLS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ISOLATE_PURIFY_IMMUNE_CELLS_WORKFLOW(ch_input)

    ISOLATE_PURIFY_IMMUNE_CELLS_WORKFLOW.out.output.view { "Output: $it" }
}
