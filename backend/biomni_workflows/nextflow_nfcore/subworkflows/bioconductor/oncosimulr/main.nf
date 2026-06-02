#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OncoSimulR
// Functions for forward population genetic simulation in asexual populations, with special focus on ca
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OncoSimulR/inst/doc/OncoSimulR.R
// Upstream  : Oncotree, devtools, graph, igraph, parallel
// Downstream: none
//
// Install: BiocManager::install("OncoSimulR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ONCOSIMULR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-oncosimulr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-oncosimulr:4.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-oncosimulr:4.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_oncosimulr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_oncosimulr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_oncosimulr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RNGkind)
    library(jsonlite)

    # --- Filter by row sum threshold [] ---
    # Key functions: rowSums

    # --- RNGkind analysis [] ---
    # Key functions: include_graphics, RNGkind, simOGraph, oncoSimulPop, samplePop, allFitnessEffects, allMutatorEffects, evalAllGenotypesFitAndMut
    evalAllGenotypes(afeT2, spPopSizes = c(100,10,10), currentTime = 49)[c(2,3), ]
    evalAllGenotypes(afeT2, spPopSizes = c(100,10,10), currentTime = 51)[c(2,3), ]
    evalAllGenotypes(afeT2, spPopSizes = c(100,10,10), currentTime = 101)[c(2,3), ]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_oncosimulr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_oncosimulr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_oncosimulr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ONCOSIMULR:", paste0("    oncosimulr: ", packageVersion("OncoSimulR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_oncosimulr_results.csv
    touch ${prefix}_oncosimulr_output.rds
    echo "BIOC_ONCOSIMULR:" > versions.yml
    echo "    oncosimulr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ONCOSIMULR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ONCOSIMULR(ch_input)

    emit:
    results  = BIOC_ONCOSIMULR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ONCOSIMULR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ONCOSIMULR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ONCOSIMULR.out.versions  // channel: path(versions.yml)
}
