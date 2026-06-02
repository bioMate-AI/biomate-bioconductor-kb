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
    library(DataFrame)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: DataFrame, SummarizedExperiment
    ---------------------------------------------------------------------
    data(OSdata)
    rowData <- DataFrame(row.names = rownames(exp), gene = rownames(exp))
    colData <- DataFrame(row.names = targets$sample, sample = as.character(targets$sample), mets = targets$mets)
    # --- Apply [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    nsel=500
    cvar <- apply(assay(se), 1, sd)
    dat <- se[tail(order(cvar), 500), ]
    # --- Cor [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    netyes <- cor(t(assay(dat)[, dat$mets == "yes"]))
    netno  <- cor(t(assay(dat)[, dat$mets == "no"]))
    netdiff <- netyes-netno
    # --- Rep [] ---
    # Key functions: melt, tri
    ---------------------------------------------------------------------
    cormat2 <- rep(1:nsel, each=nsel)
    cormat1 <- rep(1:nsel,nsel)
    el <- cbind(cormat1, cormat2, c(netdiff))
    melted <- melt(upper.tri(netdiff))
    # --- Lioness [] ---
    # Key functions: lioness, assay
    ---------------------------------------------------------------------
    cormat <- lioness(dat, netFun)
    corsub <- assay(cormat[which(row.names(cormat) %in% tosel), ])
    # --- Factor [] ---
    # Key functions: factor, makeContrasts, lmFit, fit, eBayes, topTable
    ---------------------------------------------------------------------
    group <- factor(se$mets)
    design <- model.matrix(~0+group)
    cont.matrix <- makeContrasts(yesvsno = (groupyes - groupno), levels = design)
    fit <- lmFit(corsub, design)
    # --- Unique [] ---
    # Key functions: lmFit, fit, eBayes, topTable
    ---------------------------------------------------------------------
    topgeneslist <- unique(c(toptable_edges[1:50,]))
    fit <- lmFit(exp, design)
    fit2 <- contrasts.fit(fit, cont.matrix)
    fit2e <- eBayes(fit2)

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
