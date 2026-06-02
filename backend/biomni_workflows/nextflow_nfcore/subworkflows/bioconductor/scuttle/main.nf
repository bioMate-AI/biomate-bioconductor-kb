#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scuttle
// Provides basic utility functions for performing single-cell analyses, focusing on simple normalizati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scuttle/inst/doc/misc.R
// Upstream  : BiocStyle, scRNAseq, scran
// Downstream: scater, scran, OSCA.advanced, OSCA.basic, OSCA.intro
//
// Install: BiocManager::install("scuttle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCUTTLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scuttle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scuttle:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scuttle:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_scuttle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scuttle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scuttle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scuttle)
    library(ZeiselBrainData)
    library(jsonlite)

    # --- Normalization [] ---
    # Key functions: logNormCounts
    sce <- logNormCounts(
        sce
    )


    # --- Aggregation and Summarization [] ---
    # Key functions: aggregateAcrossCells, summarizeAssayByGroup
    agg.sce <- aggregateAcrossCells(
        sce,
        ids = colData(sce)[, c("level1class", "tissue")]
    )
    agg.n <- summarizeAssayByGroup(
        sce,
        statistics = "prop.detected",
        ids = colData(sce)[, c("level1class", "tissue")]
    )


    # --- Feature Aggregation and Renaming [] ---
    # Key functions: sumCountsAcrossFeatures, uniquifyFeatureNames
    rownames(sce) <- uniquifyFeatureNames(
        rownames(sce),
        rowData(sce)$originalName
    )
    agg.feat <- sumCountsAcrossFeatures(
        sce,
        ids = list(GeneSet1 = 1:10, GeneSet2 = 11:50),
        average = TRUE,
        exprs_values = "logcounts"
    )


    # --- Data Frame Conversion [] ---
    # Key functions: makePerCellDF, makePerFeatureDF
    cell_df <- makePerCellDF(
        sce,
        features = "Tspan12"
    )
    feat_df <- makePerFeatureDF(
        sce,
        cells = head(colnames(sce), 4)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scuttle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scuttle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scuttle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCUTTLE:", paste0("    scuttle: ", packageVersion("scuttle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scuttle_results.csv
    touch ${prefix}_scuttle_output.rds
    echo "BIOC_SCUTTLE:" > versions.yml
    echo "    scuttle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCUTTLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_SCUTTLE(ch_input)

    emit:
    results  = BIOC_SCUTTLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCUTTLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCUTTLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCUTTLE.out.versions  // channel: path(versions.yml)
}
