#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TargetScore
// Infer the posterior distributions of microRNA targets by probabilistically modelling the likelihood 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TargetScore/inst/doc/TargetScore.R
// Upstream  : Biobase, DESeq, GEOquery, ROCR, TargetScoreData
// Downstream: none
//
// Install: BiocManager::install("TargetScore")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TARGETSCORE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-targetscore"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-targetscore:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-targetscore:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_targetscore_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_targetscore_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_targetscore_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TargetScore)
    library(jsonlite)

    # --- Toy [] ---
    # Key functions: rnorm, targetScore, pairs
    trmt <- c(rnorm(10,mean=0.01), rnorm(1000,mean=1), rnorm(90,mean=2)) + 1e3
    ctrl <- c(rnorm(1100,mean=1)) + 1e3
    logFC <- log2(trmt) - log2(ctrl)
    # 8 out of the 10 down-reg genes have prominent seq score A
    seqScoreA <- c(rnorm(8,mean=-2), rnorm(1092,mean=0))
    # --- Realtest [] ---
    # Key functions: files, targetScore
    extdata.dir <- system.file("extdata", package="TargetScore")
    # load test data
    load(list.files(extdata.dir, "\\.RData$", full.names=TRUE))
    myTargetScores <- lapply(mytestdata, function(x) targetScore(logFC=x$logFC, seqScores=x[,c(3,4)], tol=1e3, maxiter=200))
    names(myTargetScores) <- names(mytestdata)
    # --- Gettargetscores Demo [] ---
    # Key functions: getTargetScores, miRNA, get_precomputed_logFC, mclapply
    ## library(TargetScoreData)
    ## library(gplots)
    ##
    ## myTargetScores <- getTargetScores("hsa-miR-1", tol=1e-3, maxiter=200)
    ##
    # --- Gettargetscores Limma Demo [] ---
    # Key functions: getGEO, attr, fData, normalizeVSN
    ## # Demo using limma
    ## # download GEO data for hsa-miR-205
    ## library(limma)
    ## library(Biobase)
    ## library(GEOquery)
    # --- Roc [] ---
    # Key functions: prediction, performance, unlist, slot, frame
    ## library(ggplot2)
    ## library(scales)
    ## library(ROCR)
    ##
    ## # ROC
    # --- Gettargetscores Deseq Demo [] ---
    # Key functions: makeExampleCountDataSet, estimateSizeFactors, estimateDispersions, nbinomTest, rnorm
    ## library(DESeq)
    ##
    ## cds <- makeExampleCountDataSet()
    ##
    ## cds <- estimateSizeFactors( cds )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_targetscore_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_targetscore_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_targetscore_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TARGETSCORE:", paste0("    targetscore: ", packageVersion("TargetScore"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_targetscore_results.csv
    touch ${prefix}_targetscore_output.rds
    echo "BIOC_TARGETSCORE:" > versions.yml
    echo "    targetscore: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TARGETSCORE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TARGETSCORE(ch_input)

    emit:
    results  = BIOC_TARGETSCORE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TARGETSCORE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TARGETSCORE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TARGETSCORE.out.versions  // channel: path(versions.yml)
}
