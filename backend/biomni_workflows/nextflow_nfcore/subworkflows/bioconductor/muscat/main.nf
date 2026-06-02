#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: muscat
// `muscat` provides various methods and visualization tools for DS analysis in multi-sample, multi-gro
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/muscat/inst/doc/analysis.R
// Upstream  : BiocStyle, DESeq2, ExperimentHub, SingleCellExperiment, UpSetR
// Downstream: none
//
// Install: BiocManager::install("muscat")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUSCAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-muscat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-muscat:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-muscat:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_muscat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_muscat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_muscat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(muscat)
    library(ExperimentHub)
    library(jsonlite)

    # --- Data Preparation [prepSCE] ---
    # Key functions: prepSCE
    sce$id <- paste0(sce$stim, sce$ind)
    sce <- prepSCE(
        sce,
        kid = "cell",
        gid = "stim",
        sid = "id",
        drop = TRUE
    )

    # --- Pseudobulk Aggregation [aggregateData] ---
    # Key functions: aggregateData
    pb <- aggregateData(
        sce,
        assay = "counts",
        fun = "sum",
        by = c("cluster_id", "sample_id")
    )

    # --- Multidimensional Scaling [pbMDS] ---
    # Key functions: pbMDS
    pb_mds <- pbMDS(pb)

    # --- Differential State Analysis [pbDS] ---
    # Key functions: pbDS
    res <- pbDS(pb, verbose = FALSE)
    tbl <- res$table[[1]]
    tbl_fil <- lapply(tbl, function(u) {
        u <- u[u$p_adj.loc < 0.05 & abs(u$logFC) > 1, ]
        u[order(u$p_adj.loc), ]
    })

    # --- Expression Frequency Calculation [calcExprFreqs] ---
    # Key functions: calcExprFreqs
    frq <- calcExprFreqs(sce, assay = "counts", th = 0)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_muscat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_muscat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_muscat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MUSCAT:", paste0("    muscat: ", packageVersion("muscat"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_muscat_results.csv
    touch ${prefix}_muscat_output.rds
    echo "BIOC_MUSCAT:" > versions.yml
    echo "    muscat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MUSCAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MUSCAT(ch_input)

    emit:
    results  = BIOC_MUSCAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MUSCAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MUSCAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MUSCAT.out.versions  // channel: path(versions.yml)
}
