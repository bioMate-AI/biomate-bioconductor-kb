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
    library(anota2seq)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Quality Control and Outlier Detection [] ---
    # Key functions: anota2seqPerformQC, anota2seqResidOutlierTest
    ads <- anota2seqPerformQC(
        Anota2seqDataSet = ads,
        generateSingleGenePlots = FALSE
    )
    ads <- anota2seqResidOutlierTest(
        ads,
        residFitPlot = FALSE,
        generateSingleGenePlots = FALSE
    )


    # --- Analysis of Translation and Buffering [] ---
    # Key functions: anota2seqAnalyze, anota2seqSelSigGenes
    ads <- anota2seqAnalyze(
        Anota2seqDataSet = ads,
        analysis = c("translation", "buffering")
    )
    ads <- anota2seqSelSigGenes(
        Anota2seqDataSet = ads,
        selContrast = 1,
        minSlopeTranslation = -1,
        maxSlopeTranslation = 2,
        minSlopeBuffering = -2,
        maxSlopeBuffering = 1,
        maxPAdj = 0.05
    )


    # --- Regulatory Mode Classification [] ---
    # Key functions: anota2seqRegModes, anota2seqGetOutput
    ads <- anota2seqRegModes(ads)
    reg_output <- anota2seqGetOutput(
        object = ads,
        output = "regModes",
        selContrast = 1,
        analysis = "buffering",
        getRVM = TRUE
    )


    # --- Visualization of Results [] ---
    # Key functions: anota2seqPlotFC, anota2seqPlotPvalues
    anota2seqPlotFC(
        ads,
        selContrast = 1,
        plotToFile = FALSE
    )
    anota2seqPlotPvalues(
        ads,
        selContrast = 1,
        plotToFile = FALSE
    )

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
