#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: fishpond
// Fishpond contains methods for differential transcript and gene expression analysis of RNA-seq data u
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/fishpond/inst/doc/allelic.R
// Upstream  : SummarizedExperiment, ensembldb, limma, macrophage, tximeta
// Downstream: none
//
// Install: BiocManager::install("fishpond")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FISHPOND {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fishpond"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fishpond:2.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fishpond:2.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fishpond_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fishpond_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fishpond_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(fishpond)
    library(jsonlite)

    # --- Labelkeep [] ---
    # Key functions: labelKeep, swish
    ---------------------------------------------------------------------
    y <- labelKeep(y)
    y <- swish(y, x="allele", pair="sample", fast=1)
    # --- Mcols [] ---
    # Key functions: mcols
    ---------------------------------------------------------------------
    mcols(y)[1:2,c("stat","qvalue")]
    # --- Hist [] ---
    # Key functions: mcols
    ---------------------------------------------------------------------
    hist(mcols(y)[-c(1:6),"pvalue"])
    # --- Plotinfreps [] ---
    # Key functions: plotInfReps
    ---------------------------------------------------------------------
    plotInfReps(y, idx=1, x="allele", cov="condition",
                xaxis=FALSE, legend=TRUE, legendPos="bottomright")
    # --- Labelkeep [] ---
    # Key functions: labelKeep, swish
    ---------------------------------------------------------------------
    y <- labelKeep(y)
    y <- swish(y, x="allele", pair="sample", cov="time", cor="pearson")
    # --- Mcols [] ---
    # Key functions: mcols
    ---------------------------------------------------------------------
    mcols(y)[1:2,c("stat","qvalue")]
    # --- Computeinfrv [] ---
    # Key functions: computeInfRV
    ---------------------------------------------------------------------
    y <- computeInfRV(y)
    # --- Cut [] ---
    # Key functions: cut
    ---------------------------------------------------------------------
    y$time_bins <- cut(y$time,breaks=c(0,.25,.75,1),
                       include.lowest=TRUE, labels=FALSE)
    y$time_bins <- paste0("time-",y$time_bins)
    table(y$time_bins[ y$allele == "a2" ])
    # --- Grep [] ---
    # Key functions: assayNames, assay
    ---------------------------------------------------------------------
    reps <- grep("infRep", assayNames(y), value=TRUE)
    for (k in reps) {
      assay(y,k)[1,21:40] <- assay(y,k)[1,c(31:40,21:30)]
    }
    # --- Which [] ---
    # Key functions: equal, covariate
    ---------------------------------------------------------------------
    pc <- 5 # a pseudocount
    idx1 <- which(y$allele == "a1")
    idx2 <- which(y$allele == "a2")
    # the sample must be aligned
    # --- Grep [] ---
    # Key functions: assayNames, assays, abind
    ---------------------------------------------------------------------
    reps <- grep("infRep", assayNames(y), value=TRUE)
    nreps <- length(reps)
    infReps <- assays(y)[reps]
    infRepsArray <- abind::abind(as.list(infReps), along=3)
    # --- Function [] ---
    # Key functions: lmFit
    ---------------------------------------------------------------------
    computeStat <- function(k, design, name) {
      fit <- limma::lmFit(lfcArray[,,k], design)
      tstats <- fit$coef/fit$stdev.unscaled/fit$sigma
      tstats[,name]
    # --- Rowmeans [] ---
    # Key functions: rowMeans, computeStat
    ---------------------------------------------------------------------
    stat <- rowMeans(sapply(1:nreps, \(k) computeStat(k, design, "groupB:cov")))
    # --- Nrow [] ---
    # Key functions: sample, rowMeans
    ---------------------------------------------------------------------
    n <- nrow(design)
    nperms <- 100
    nulls <- matrix(nrow=nrow(y), ncol=nperms)
    set.seed(1)
    # --- Emppvals [] ---
    # Key functions: empPvals, qvalue, frame
    ---------------------------------------------------------------------
    pvalue <- qvalue::empPvals(abs(stat), abs(nulls))
    q_res <- qvalue::qvalue(pvalue)
    locfdr <- q_res$lfdr
    qvalue <- q_res$qvalues

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fishpond_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fishpond_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fishpond_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FISHPOND:", paste0("    fishpond: ", packageVersion("fishpond"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fishpond_results.csv
    touch ${prefix}_fishpond_output.rds
    echo "BIOC_FISHPOND:" > versions.yml
    echo "    fishpond: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FISHPOND_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FISHPOND(ch_input)

    emit:
    results  = BIOC_FISHPOND.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FISHPOND.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FISHPOND.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FISHPOND.out.versions  // channel: path(versions.yml)
}
