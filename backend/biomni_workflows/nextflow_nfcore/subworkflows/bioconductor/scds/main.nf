#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scds
// In single cell RNA sequencing (scRNA-seq) data combinations of cells are sometimes considered a sing
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scds/inst/doc/scds.R
// Upstream  : Rtsne, cowplot, devtools, rsvd, scater
// Downstream: none
//
// Install: BiocManager::install("scds")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCDS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scds"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scds:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scds:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scds_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scds_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scds_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scds)
    library(jsonlite)

    # --- logcounts [] ---
    # Key functions: logcounts, reducedDim, plotReducedDim
    logcounts(sce) = log1p(counts(sce))
    vrs            = apply(logcounts(sce),1,var)
    pc             = rpca(t(logcounts(sce)[order(vrs,decreasing=TRUE)[1:100],]))
    # --- plot_grid [] ---
    # Key functions: plot_grid
    top3 = metadata(sce)$cxds$topPairs[1:3,]
    rs   = rownames(sce)
    hb   = rowData(sce)$cxds_hvg_bool

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scds_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scds_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scds_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCDS:", paste0("    scds: ", packageVersion("scds"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scds_results.csv
    touch ${prefix}_scds_output.rds
    echo "BIOC_SCDS:" > versions.yml
    echo "    scds: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCDS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCDS(ch_input)

    emit:
    results  = BIOC_SCDS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCDS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCDS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCDS.out.versions  // channel: path(versions.yml)
}
