#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: les
// The 'les' package estimates Loci of Enhanced Significance (LES) in tiling microarray data. These are
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/les/inst/doc/les.R
// Upstream  : limma
// Downstream: none
//
// Install: BiocManager::install("les")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-les"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-les:1.56.0--r44_0' :
        'quay.io/biocontainers/bioconductor-les:1.56.0--r44_0'}"

    input:
    tuple val(meta), path(model_object)

    output:
    tuple val(meta), path("${meta.id}_les_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_les_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_les_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Les)
    library(jsonlite)

    # --- Estimateprobelevelstatistics [] ---
    # Key functions: lmFit, eBayes
    library(limma)
    design <- cbind(offset=1, diff=condition)
    fit <- lmFit(exprs, design)
    fit <- eBayes(fit)
    pval <- fit$p.value[, "diff"]
    # --- Plotprobelevelstatistics [] ---
    # Key functions: getOption, expression
    getOption("SweaveHooks")[["fig"]]()
    plot(pos, pval, pch=20, xlab="Probe position", ylab=expression(p))
    abline(v=region)
    # --- Constructles [] ---
    # Key functions: Les
    res <- Les(pos, pval)
    # --- Estimateles [] ---
    # Key functions: estimate
    res <- estimate(res, win=200)
    # --- Showplotles [] ---
    # Key functions: getOption
    getOption("SweaveHooks")[["fig"]]()
    res
    summary(res)
    plot(res)
    abline(v=region)
    # --- Showplotles2 [] ---
    # Key functions: getOption, estimate
    getOption("SweaveHooks")[["fig"]]()
    res2 <- estimate(res, win=200, weighting=rectangWeight)
    res2
    plot(res2)
    abline(v=region)
    # --- Threshold [] ---
    # Key functions: threshold
    res2 <- threshold(res2, grenander=TRUE, verbose=TRUE)
    # --- Regions [] ---
    # Key functions: regions
    res2 <- regions(res2, verbose=TRUE)
    res2
    res2["regions"]
    # --- Plotregions [] ---
    # Key functions: getOption
    getOption("SweaveHooks")[["fig"]]()
    plot(res2, region=TRUE)
    abline(v=region)
    # --- Plotci [] ---
    # Key functions: getOption, ci
    getOption("SweaveHooks")[["fig"]]()
    subset <- pos >= 5232400 & pos <= 5233100
    res2 <- ci(res2, subset, nBoot=50, alpha=0.1)
    plot(res2, error="ci", region=TRUE)
    # --- Plotoptions [] ---
    # Key functions: getOption
    getOption("SweaveHooks")[["fig"]]()
    plot(res2, error="ci", region=TRUE, rug=TRUE, xlim=c(5232000, 5233000), sigArgs=list(col="firebrick4"), plotArgs=list(main="LES results", yaxp=c(0, 1, 2)), limitArgs=list(lty=2, lwd=3), regionArgs=list(col="black", density=20), probeArgs=list(col="dodgerblue4", type="p"))
    # --- Export [] ---
    # Key functions: tempfile, export
    bedFile <- paste(tempfile(), "bed", sep=".")
    gffFile <- paste(tempfile(), "gff", sep=".")
    wigFile <- paste(tempfile(), "wig", sep=".")
    export(res2, bedFile)
    export(res2, gffFile, format="gff")
    # --- Customweightingfunction [] ---
    # Key functions: estimate
    weightFoo <- function(distance, win) {
    weight <- 1 - distance/win
    return(weight)
    }
    resFoo <- estimate(res, 200, weighting=weightFoo)
    # --- Chi2 [] ---
    # Key functions: chi2
    ## regions <- res["regions"]
    ## winsize <- seq(100, 300, by=20)
    ## res2 <- chi2(res2, winsize, regions, offset=2500)
    ## plot(winsize, x["chi2"], type="b")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_les_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_les_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_les_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LES:", paste0("    les: ", packageVersion("les"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_les_results.csv
    touch ${prefix}_les_output.rds
    echo "BIOC_LES:" > versions.yml
    echo "    les: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(model_object) ]

    main:
    BIOC_LES(ch_input)

    emit:
    results  = BIOC_LES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LES.out.versions  // channel: path(versions.yml)
}
