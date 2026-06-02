#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FRASER
// Detection of rare aberrant splicing events in transcriptome profiles. Read count ratio expectations 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FRASER/inst/doc/FRASER.R
// Upstream  : BiocParallel
// Downstream: none
//
// Install: BiocManager::install("FRASER")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FRASER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fraser"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fraser:2.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fraser:2.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fraser_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fraser_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fraser_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FRASER)
    library(FraserDataSet)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Splicing Metric Calculation and Filtering [] ---
    # Key functions: calculatePSIValues, filterExpressionAndVariability, plotFilterExpression
    fds <- calculatePSIValues(fds)
    fds <- filterExpressionAndVariability(
        fds,
        minExpressionInOneSample=20,
        minDeltaPsi=0.0,
        filter=TRUE
    )
    plotFilterExpression(fds, bins=100)


    # --- Hyperparameter Optimization [] ---
    # Key functions: optimHyperParams, bestQ
    fds <- optimHyperParams(
        fds,
        type="jaccard",
        plot=FALSE
    )
    opt_q <- bestQ(fds, type="jaccard")


    # --- Model Fitting and Confounder Correction [] ---
    # Key functions: FRASER, fit, plotCountCorHeatmap
    fds <- FRASER(fds, q=c(jaccard=2))
    fds <- fit(
        fds,
        q=3,
        type="jaccard",
        implementation="PCA-BB-Decoder",
        iterations=2
    )
    plotCountCorHeatmap(
        fds,
        type="jaccard",
        logit=TRUE,
        normalized=TRUE
    )


    # --- Annotation and Splicing Analysis [] ---
    # Key functions: annotateRangesWithTxDb, calculatePadjValues, results
    fds <- annotateRangesWithTxDb(
        fds,
        txdb=txdb,
        orgDb=orgDb
    )
    fds <- calculatePadjValues(
        fds,
        type="jaccard",
        geneLevel=TRUE
    )
    res <- results(fds, aggregate=TRUE, all=TRUE)


    # --- Visualization and Export [] ---
    # Key functions: plotVolcano, saveFraserDataSet, workingDir, name
    plotVolcano(
        fds,
        sampleID="sample1",
        type="jaccard",
        aggregate=TRUE
    )
    workingDir(fds) <- "FRASER_output"
    name(fds) <- "ExampleAnalysis"
    saveFraserDataSet(fds, dir=workingDir(fds), name=name(fds))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fraser_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fraser_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fraser_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FRASER:", paste0("    fraser: ", packageVersion("FRASER"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fraser_results.csv
    touch ${prefix}_fraser_output.rds
    echo "BIOC_FRASER:" > versions.yml
    echo "    fraser: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FRASER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FRASER(ch_input)

    emit:
    results  = BIOC_FRASER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FRASER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FRASER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FRASER.out.versions  // channel: path(versions.yml)
}
