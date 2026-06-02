#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: lionessR
// LIONESS, or Linear Interpolation to Obtain Network Estimates for Single Samples, can be used to reco
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/lionessR/inst/doc/lionessR.R
// Upstream  : SummarizedExperiment, igraph, limma, reshape2
// Downstream: none
//
// Install: BiocManager::install("lionessR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LIONESSR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lionessr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lionessr:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lionessr:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lionessr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lionessr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lionessr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(lionessR)
    library(DataFrame)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Single-Sample Network Reconstruction [] ---
    # Key functions: lioness
    netFun <- function(x) {
        cor(t(x))
    }
    cormat <- lioness(dat, netFun)


    # --- Differential Network Analysis [] ---
    # Key functions: lmFit, contrasts.fit, eBayes, topTable
    group <- factor(dat$mets)
    design <- model.matrix(~0 + group)
    colnames(design) <- c("no", "yes")
    cont.matrix <- makeContrasts(yesvsno = (yes - no), levels = design)
    fit <- lmFit(assay(cormat), design)
    fit2 <- contrasts.fit(fit, cont.matrix)
    fit2e <- eBayes(fit2)
    toptable <- topTable(fit2e, number = 100, adjust = "fdr")


    # --- Network Visualization [] ---
    # Key functions: graph.data.frame
    toptable_edges <- t(matrix(unlist(strsplit(row.names(toptable), "_")), 2))
    z <- cbind(toptable_edges[1:50, ], toptable$logFC[1:50])
    g <- graph.data.frame(z, directed = FALSE)
    E(g)$weight <- as.numeric(z[, 3])
    E(g)$color <- ifelse(E(g)$weight < 0, "blue", "red")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lionessr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lionessr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lionessr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LIONESSR:", paste0("    lionessr: ", packageVersion("lionessR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lionessr_results.csv
    touch ${prefix}_lionessr_output.rds
    echo "BIOC_LIONESSR:" > versions.yml
    echo "    lionessr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LIONESSR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LIONESSR(ch_input)

    emit:
    results  = BIOC_LIONESSR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LIONESSR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LIONESSR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LIONESSR.out.versions  // channel: path(versions.yml)
}
