#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rqubic
// This package implements the QUBIC algorithm introduced by Li et al. for the qualitative biclustering
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rqubic/inst/doc/rqubic.R
// Upstream  : Biobase, biclust
// Downstream: none
//
// Install: BiocManager::install("rqubic")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RQUBIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rqubic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rqubic:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rqubic:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rqubic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rqubic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rqubic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rqubic)
    library(jsonlite)

    # --- Helpparser [] ---
    # Key functions: example
    ## library(rqubic)
    ## library(Biobase)
    ## library(biclust)
    ## help("parseQubicRules")
    ## example(parseQubicRules)
    # --- Quantile [] ---
    # Key functions: quantileDiscretize
    demo.disc <- quantileDiscretize(demo.exprs)
    # --- Biclust [] ---
    # Key functions: quBicluster
    demo.bic <- quBicluster(demo.seed, demo.disc)
    demo.bic
    # --- Biclustvis [] ---
    # Key functions: parallelCoordinates
    parallelCoordinates(BicatYeast, demo.bic, number=3, plotBoth=FALSE,
                        compare=TRUE, col="#004495", pch=1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rqubic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rqubic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rqubic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RQUBIC:", paste0("    rqubic: ", packageVersion("rqubic"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rqubic_results.csv
    touch ${prefix}_rqubic_output.rds
    echo "BIOC_RQUBIC:" > versions.yml
    echo "    rqubic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RQUBIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RQUBIC(ch_input)

    emit:
    results  = BIOC_RQUBIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RQUBIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RQUBIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RQUBIC.out.versions  // channel: path(versions.yml)
}
