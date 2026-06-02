#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: anota2seq
// anota2seq provides analysis of translational efficiency and differential expression analysis for pol
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/anota2seq/inst/doc/anota2seq.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("anota2seq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANOTA2SEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-anota2seq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-anota2seq:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-anota2seq:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_anota2seq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_anota2seq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_anota2seq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SummarizedExperiment)
    library(jsonlite)

    # --- anota2seq Data Set From Matrix [] ---
    # Key functions: anota2seqDataSetFromMatrix, anota2seqRun
    ads <- anota2seqDataSetFromMatrix(
    ads <- anota2seqRun(ads)
    # --- anota2seq Plot F C [] ---
    # Key functions: anota2seqPlotFC
    anota2seqPlotFC(ads, selContrast = 1, plotToFile = FALSE)
    # --- gettingStarted getListOfSignificantGenes translation [] ---
    # Key functions: anota2seqGetOutput
    head(
    anota2seqGetOutput(
    selContrast = 1)[, c("apvEff", "apvRvmPAdj", "singleRegMode")])
    # --- initialize object from matrix [] ---
    # Key functions: anota2seqDataSetFromMatrix
    ads <- anota2seqDataSetFromMatrix(
    # --- prepare SE [] ---
    # Key functions: SummarizedExperiment
    library(SummarizedExperiment)
    countData <- as.matrix(cbind(anota2seq_data_P[1:1000,],anota2seq_data_T[1:1000,]))
    anot <- data.frame(
    # --- initialize object from SE [] ---
    # Key functions: anota2seqDataSetFromSE
    adsFromSE <- anota2seqDataSetFromSE(
    assayNum = 1, # Position of the count data in assays(mySummarizedExperiment)
    # --- assess model assumptions [] ---
    # Key functions: anota2seqPerformQC
    ads <- anota2seqPerformQC(Anota2seqDataSet = ads,
    # --- assess model assumptions echoFALSE [] ---
    # Key functions: anota2seqPerformQC
    ads <- anota2seqPerformQC(Anota2seqDataSet = ads,
    # --- assess model assumptions2 [] ---
    # Key functions: anota2seqResidOutlierTest
    anota2seqResidOutlierTest(ads, residFitPlot = FALSE,
    # --- assess model assumptions2 echoFALSE [] ---
    # Key functions: anota2seqResidOutlierTest
    ads <- anota2seqResidOutlierTest(ads, residFitPlot = FALSE, generateSingleGenePlots = TRUE, nGraphs = 12)
    file.rename(from = "ANOTA2SEQ_residual_distributions_single.pdf", to = "figure/ANOTA2SEQ_residual_distributions_single.pdf")
    file.rename(from = "ANOTA2SEQ_residual_distribution_summary.jpeg", to = "figure/ANOTA2SEQ_residual_distribution_summary.jpeg")
    # --- analysis translation and buffering [] ---
    # Key functions: anota2seqAnalyze
    ads <- anota2seqAnalyze(Anota2seqDataSet = ads,
    analysis = c("translation", "buffering"))
    # --- analysis translation and buffering echoFALSE [] ---
    # Key functions: anota2seqAnalyze
    ads <- anota2seqAnalyze(Anota2seqDataSet = ads,
    analysis = c("translation", "buffering"),
    # --- anota2seq Plot Pvalues [] ---
    # Key functions: anota2seqPlotPvalues
    par(mfrow = c(1, 2))
    anota2seqPlotPvalues(ads, selContrast = 1, plotToFile = FALSE)
    # --- selSigGenes translation buffering [] ---
    # Key functions: anota2seqSelSigGenes
    ads <- anota2seqSelSigGenes(Anota2seqDataSet = ads,
    # --- singleGeneRegressions translation [] ---
    # Key functions: anota2seqPlotGenes
    anota2seqPlotGenes(ads, selContrast = 1, analysis = "translation", plotToFile = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_anota2seq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_anota2seq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_anota2seq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANOTA2SEQ:", paste0("    anota2seq: ", packageVersion("anota2seq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_anota2seq_results.csv
    touch ${prefix}_anota2seq_output.rds
    echo "BIOC_ANOTA2SEQ:" > versions.yml
    echo "    anota2seq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANOTA2SEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANOTA2SEQ(ch_input)

    emit:
    results  = BIOC_ANOTA2SEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANOTA2SEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANOTA2SEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANOTA2SEQ.out.versions  // channel: path(versions.yml)
}
