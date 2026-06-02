#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CatsCradle
// This package addresses two broad areas.  It allows for in-depth analysis of spatial transcriptomic d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CatsCradle/inst/doc/CatsCradle.R
// Upstream  : pheatmap, tictoc
// Downstream: none
//
// Install: BiocManager::install("CatsCradle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CATSCRADLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-catscradle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-catscradle:1.0.1--r44_0' :
        'quay.io/biocontainers/bioconductor-catscradle:1.0.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_catscradle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_catscradle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_catscradle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CatsCradle)
    library(DimPlot)
    library(jsonlite)

    # --- Object Transposition ---
    # Key functions: make.getExample, transposeObject
    getExample <- make.getExample()
    exSeuratObj <- getExample("exSeuratObj")
    STranspose <- transposeObject(exSeuratObj)

    # --- Co-clustering Expression Matrix ---
    # Key functions: getAverageExpressionMatrix, tagRowAndColNames
    averageExpMatrix <- getAverageExpressionMatrix(
        exSeuratObj,
        STranspose,
        layer = "data"
    )
    taggedMatrix <- tagRowAndColNames(
        averageExpMatrix,
        ccTag = "cellClusters_",
        gcTag = "geneClusters_"
    )

    # --- Gene Set Clustering Statistics ---
    # Key functions: make.getExample, getObjectSubsetClusteringStatistics
    getExample <- make.getExample()
    hallmark <- getExample("hallmark")
    g2mGenes <- intersect(
        colnames(STranspose),
        hallmark[["HALLMARK_G2M_CHECKPOINT"]]
    )
    stats <- getObjectSubsetClusteringStatistics(
        STranspose,
        g2mGenes,
        numTrials = 100
    )

    # --- Spatial Neighborhood Analysis ---
    # Key functions: make.getExample, meanZPerClusterOnUMAP, getNearbyGenes
    getExample <- make.getExample()
    hallmark <- getExample("hallmark")
    meanZDF <- meanZPerClusterOnUMAP(
        exSeuratObj,
        STranspose,
        "shortName"
    )
    geneSet <- intersect(
        colnames(STranspose),
        hallmark[["HALLMARK_INTERFERON_ALPHA_RESPONSE"]]
    )
    geomNearby <- getNearbyGenes(
        STranspose,
        geneSet,
        radius = 0.2,
        metric = "umap"
    )

    # --- Functional Annotation and Prediction ---
    # Key functions: annotateGenesByGeneSet, annotateGeneAsVector, predictAnnotation
    getExample <- make.getExample()
    hallmark <- getExample("hallmark")
    annotatedGenes <- annotateGenesByGeneSet(hallmark)
    mycVector <- annotateGeneAsVector("Myc", hallmark, normalised = TRUE)
    predictedMyc <- predictAnnotation(
        "Myc",
        hallmark,
        STranspose,
        radius = 0.5
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_catscradle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_catscradle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_catscradle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CATSCRADLE:", paste0("    catscradle: ", packageVersion("CatsCradle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_catscradle_results.csv
    touch ${prefix}_catscradle_output.rds
    echo "BIOC_CATSCRADLE:" > versions.yml
    echo "    catscradle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CATSCRADLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CATSCRADLE(ch_input)

    emit:
    results  = BIOC_CATSCRADLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CATSCRADLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CATSCRADLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CATSCRADLE.out.versions  // channel: path(versions.yml)
}
