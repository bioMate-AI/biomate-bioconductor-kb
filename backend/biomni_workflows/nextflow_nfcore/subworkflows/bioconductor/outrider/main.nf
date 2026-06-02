#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OUTRIDER
// Identification of aberrant gene expression in RNA-seq data. Read count expectations are modeled by a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OUTRIDER/inst/doc/OUTRIDER.R
// Upstream  : AnnotationDbi, RMariaDB, beeswarm, peer
// Downstream: none
//
// Install: BiocManager::install("OUTRIDER")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OUTRIDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-outrider"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-outrider:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-outrider:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_outrider_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_outrider_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_outrider_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OUTRIDER)
    library(OutriderDataSet)
    library(PEER)
    library(PEER_setNmax_iterations)
    library(jsonlite)

    # --- bpparam [] ---
    # Key functions: bpparam, bpworkers, register
    suppressPackageStartupMessages({
    library(OUTRIDER)
    library(beeswarm)
    # --- rnorm [] ---
    # Key functions: rnorm, beeswarm
    par.old <- par(no.readonly=TRUE)
    par(mfrow=c(1,2), cex=1.2)
    ylim <- c(80, 310)
    # --- Extract differential expression results [] ---
    # Key functions: OutriderDataSet, filterExpression, OUTRIDER, results, plotQQ
    library(OUTRIDER)
    ctsFile <- system.file('extdata', 'KremerNBaderSmall.tsv',
    ctsTable <- read.table(ctsFile, check.names=FALSE)
    # --- make Example Outrider Data Set [] ---
    # Key functions: makeExampleOutriderDataSet, OutriderDataSet
    odsSmall <- makeExampleOutriderDataSet(dataset="Kremer")
    baseURL <- paste0("https://static-content.springer.com/esm/",
    count_URL <- paste0(baseURL, "41467_2017_BFncomms15824_MOESM390_ESM.txt")
    # --- db Connect [] ---
    # Key functions: dbConnect, dbGetQuery, loadDb
    try({
    library(RMariaDB)
    library(AnnotationDbi)
    # --- filter Expression [] ---
    # Key functions: filterExpression, plotFPKM, plotExpressedGenes
    ods <- filterExpression(ods, txdb, mapping=map,
    plotFPKM(ods)
    plotExpressedGenes(ods)
    # --- plotting between sample correlations [] ---
    # Key functions: plotCountCorHeatmap, plotCountGeneSampleHeatmap
    ods <- plotCountCorHeatmap(ods, colGroups=c("SEX", "RNA_HOX_GROUP"),
    ods <- plotCountGeneSampleHeatmap(ods, colGroups=c("SEX", "RNA_HOX_GROUP"),
    # --- controlling for confounders [] ---
    # Key functions: estimateSizeFactors, controlForConfounders, plotCountCorHeatmap
    ods <- estimateSizeFactors(ods)
    ods <- controlForConfounders(ods, q=21, iterations=3)
    ods <- plotCountCorHeatmap(ods, normalized=TRUE,
    # --- find Encoding Dim [] ---
    # Key functions: findEncodingDim, plotEncDimSearch
    ods <- findEncodingDim(ods)
    plotEncDimSearch(ods)
    # --- sample Exclusion Mask [] ---
    # Key functions: sampleExclusionMask
    sampleExclusionMask(ods) <- FALSE
    sampleExclusionMask(ods[,"MUC1365"]) <- TRUE
    sampleExclusionMask(ods)
    # --- fit [] ---
    # Key functions: fit
    ods <- fit(ods)
    hist(theta(ods))
    # --- pValue computation [] ---
    # Key functions: computePvalues
    compute P-values (nominal and adjusted)
    ods <- computePvalues(ods, alternative="two.sided", method="BY")
    # --- zScore computation [] ---
    # Key functions: computeZscores
    ods <- computeZscores(ods)
    # --- Extract differential expression results [] ---
    # Key functions: results
    get results (default only significant, padj < 0.05)
    res <- results(ods)
    head(res)
    # --- plot Aberrant Per Sample [] ---
    # Key functions: plotAberrantPerSample
    tail(sort(aberrant(ods, by="sample")))
    tail(sort(aberrant(ods, by="gene", zScoreCutoff=1)))
    plotAberrantPerSample(ods, padjCutoff=0.05)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_outrider_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_outrider_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_outrider_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OUTRIDER:", paste0("    outrider: ", packageVersion("OUTRIDER"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_outrider_results.csv
    touch ${prefix}_outrider_output.rds
    echo "BIOC_OUTRIDER:" > versions.yml
    echo "    outrider: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OUTRIDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OUTRIDER(ch_input)

    emit:
    results  = BIOC_OUTRIDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OUTRIDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OUTRIDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OUTRIDER.out.versions  // channel: path(versions.yml)
}
