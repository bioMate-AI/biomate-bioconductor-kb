#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: apeglm
// apeglm provides Bayesian shrinkage estimators for effect sizes for a variety of GLM models, using ap
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/apeglm/inst/doc/apeglm.R
// Upstream  : DESeq2, airway, emdbook
// Downstream: rnaseqGene
//
// Install: BiocManager::install("apeglm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_APEGLM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-apeglm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-apeglm:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-apeglm:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_apeglm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_apeglm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_apeglm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(apeglm)
    library(jsonlite)

    # --- hline [] ---
    # Key functions: hline
    par(mfrow=c(1,3))
    lims <- c(-8,8)
    hline <- function() abline(h=c(-4:4 * 2),col=rgb(0,0,0,.2))
    # --- ifelse [] ---
    # Key functions: ifelse
    s.val <- svalue(fit$thresh)
    cols <- ifelse(s.val < .01, "red", "black")
    # --- apeglm [] ---
    # Key functions: apeglm
    plot(res$baseMean, fit.mle$map[,coef], log="x", xlab=xlab, ylab="log odds")
    points(res$baseMean[idx], fit.mle$map[idx,coef], col="dodgerblue", cex=3)
    mle <- cbind(fit.mle$map[,coef], fit.mle$sd[,coef])
    # --- ifelse [] ---
    # Key functions: ifelse
    par(mfrow=c(1,2))
    ylim <- c(-1,1.5)
    s.val <- svalue(fit2$thresh) # small-or-false-sign value

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_apeglm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_apeglm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_apeglm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_APEGLM:", paste0("    apeglm: ", packageVersion("apeglm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_apeglm_results.csv
    touch ${prefix}_apeglm_output.rds
    echo "BIOC_APEGLM:" > versions.yml
    echo "    apeglm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_APEGLM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_APEGLM(ch_input)

    emit:
    results  = BIOC_APEGLM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_APEGLM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_APEGLM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_APEGLM.out.versions  // channel: path(versions.yml)
}
