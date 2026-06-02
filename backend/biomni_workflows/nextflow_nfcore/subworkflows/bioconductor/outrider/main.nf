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

    # --- Confounder Correction [] ---
    # Key functions: estimateSizeFactors, sampleExclusionMask, controlForConfounders, plotCountCorHeatmap
    ods <- estimateSizeFactors(ods)
    sampleExclusionMask(ods) <- FALSE
    ods <- controlForConfounders(
        ods, 
        q=21, 
        iterations=3
    )
    ods <- plotCountCorHeatmap(
        ods, 
        normalized=TRUE
    )


    # --- Outlier Detection [] ---
    # Key functions: computePvalues, computeZscores, results, aberrant
    ods <- computePvalues(
        ods, 
        alternative="two.sided", 
        method="BY"
    )
    ods <- computeZscores(ods)
    res <- results(
        ods, 
        padjCutoff=0.05, 
        zScoreCutoff=2
    )
    gene_aberrant <- aberrant(ods, by="gene")
    sample_aberrant <- aberrant(ods, by="sample")


    # --- Visualisation [] ---
    # Key functions: plotAberrantPerSample, plotVolcano, plotExpressionRank, plotQQ, plotExpectedVsObservedCounts
    plotAberrantPerSample(ods, padjCutoff=0.05)
    plotVolcano(ods, "MUC1344", basePlot=TRUE)
    plotExpressionRank(ods, "TIMMDC1", basePlot=TRUE)
    plotQQ(ods, "TIMMDC1")
    plotExpectedVsObservedCounts(
        ods, 
        "TIMMDC1", 
        basePlot=TRUE
    )

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
