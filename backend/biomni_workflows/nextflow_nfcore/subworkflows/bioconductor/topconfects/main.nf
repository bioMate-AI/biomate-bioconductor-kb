#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: topconfects
// Rank results by confident effect sizes, while maintaining False Discovery Rate and False Coverage-st
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/topconfects/inst/doc/fold_change.R
// Upstream  : DESeq2, NBPSeq, dplyr, edgeR, ggplot2
// Downstream: none
//
// Install: BiocManager::install("topconfects")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TOPCONFECTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-topconfects"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-topconfects:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-topconfects:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_topconfects_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_topconfects_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_topconfects_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DGEList)
    library(jsonlite)

    # --- Create DGEList count object [] ---
    # Key functions: group_by, summarize, DGEList, rowSums, calcNormFactors
    library(topconfects)
    library(NBPSeq)
    library(edgeR)
    # --- Precision weights with voom (limma) [] ---
    # Key functions: voom, lmFit
    design <- model.matrix(~Time+Treat)
    voom(y, design) %>%
    lmFit(design)
    # --- limma_confects [] ---
    # Key functions: limma_confects
    confects <- limma_confects(fit, coef="Treathrcc", fdr=0.05)
    # --- QL F-test model fit (edgeR) [] ---
    # Key functions: estimateDisp, glmQLFit
    y <- estimateDisp(y, design, robust=TRUE)
    efit <- glmQLFit(y, design, robust=TRUE)
    # --- edger_confects [] ---
    # Key functions: edger_confects
    econfects <- edger_confects(efit, coef="Treathrcc", fdr=0.05, step=0.05)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_topconfects_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_topconfects_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_topconfects_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TOPCONFECTS:", paste0("    topconfects: ", packageVersion("topconfects"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_topconfects_results.csv
    touch ${prefix}_topconfects_output.rds
    echo "BIOC_TOPCONFECTS:" > versions.yml
    echo "    topconfects: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TOPCONFECTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TOPCONFECTS(ch_input)

    emit:
    results  = BIOC_TOPCONFECTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TOPCONFECTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TOPCONFECTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TOPCONFECTS.out.versions  // channel: path(versions.yml)
}
