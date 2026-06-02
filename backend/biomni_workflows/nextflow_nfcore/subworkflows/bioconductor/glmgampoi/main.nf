#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: glmGamPoi
// Fit linear models to overdispersed count data. The package can estimate the overdispersion and fit r
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/glmGamPoi/inst/doc/glmGamPoi.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("glmGamPoi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GLMGAMPOI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-glmgampoi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-glmgampoi:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-glmgampoi:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_glmgampoi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_glmgampoi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_glmgampoi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(glmGamPoi)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set, rnbinom, glm_gp
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )
    set.seed(2)

    ## -----------------------------------------------------------------------------
    library(glmGamPoi)

    ## -----------------------------------------------------------------------------
    # overdispersion = 1/size
    counts <- rnbinom(n = 10, mu = 5, size = 1/0.7)

    # design = ~ 1 means that an intercept-only model is fit
    fit <- glm_gp(counts, design = ~ 1)

    # --- Warning=false [] ---
    # Key functions: TENxPBMCData, rowSums2, assay, sample, glm_gp, pbmc4k
    library(SummarizedExperiment)
    library(DelayedMatrixStats)

    ## -----------------------------------------------------------------------------
    # The full dataset with 33,000 genes and 4340 cells
    # The first time this is run, it will download the data
    pbmcs <- TENxPBMCData::TENxPBMCData("pbmc4k")

    # I want genes where at least some counts are non-zero
    non_empty_rows <- which(rowSums2(assay(pbmcs)) > 0)
    pbmcs_subset <- pbmcs[sample(non_empty_rows, 300), ]
    pbmcs_subset

    ## -----------------------------------------------------------------------------
    fit <- glm_gp(pbmcs_subset, on_disk = FALSE)

    # --- Warning=false [] ---
    # Key functions: assay, mark, glm_gp, suppressMessages, DESeqDataSetFromMatrix, estimateSizeFactors, poscounts
    # Explicitly realize count matrix in memory so that it is a fair comparison
    pbmcs_subset <- as.matrix(assay(pbmcs_subset))
    model_matrix <- matrix(1, nrow = ncol(pbmcs_subset))


    # --- Coefficient Comparison [] ---
    # Key functions: par, abline, assay, glmGamPoi, edgeR
    par(mfrow = c(2, 4), cex.main = 2, cex.lab = 1.5)
    plot(fit$Beta[,1], coef(dds)[,1] / log2(exp(1)), pch = 16, 
         main = "Beta Coefficients", xlab = "glmGamPoi", ylab = "DESeq2")
    abline(0,1)
    plot(fit$Beta[,1], edgeR_fit$unshrunk.coefficients[,1], pch = 16,
         main = "Beta Coefficients", xlab = "glmGamPoi", ylab = "edgeR")
    abline(0,1)

    plot(fit$Mu[,1], assay(dds, "mu")[,1], pch = 16, log="xy",
         main = "Gene Mean", xlab = "glmGamPoi", ylab = "DESeq2")
    abline(0,1)
    plot(fit$Mu[,1], edgeR_fit$fitted.values[,1], pch = 16, log="xy",
         main = "Gene Mean", xlab = "glmGamPoi", ylab = "edgeR")
    abline(0,1)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_glmgampoi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_glmgampoi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_glmgampoi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GLMGAMPOI:", paste0("    glmgampoi: ", packageVersion("glmGamPoi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_glmgampoi_results.csv
    touch ${prefix}_glmgampoi_output.rds
    echo "BIOC_GLMGAMPOI:" > versions.yml
    echo "    glmgampoi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GLMGAMPOI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GLMGAMPOI(ch_input)

    emit:
    results  = BIOC_GLMGAMPOI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GLMGAMPOI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GLMGAMPOI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GLMGAMPOI.out.versions  // channel: path(versions.yml)
}
