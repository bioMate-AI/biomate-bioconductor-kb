#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PIUMA
// The PIUMA package offers a tidy pipeline of Topological Data Analysis frameworks to identify and cha
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PIUMA/inst/doc/PIUMA_vignette.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("PIUMA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PIUMA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-piuma"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-piuma:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-piuma:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_piuma_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_piuma_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_piuma_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PIUMA)
    library(Anchoring)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Dimensionality Reduction and Projection [] ---
    # Key functions: dfToDistance, dfToProjection, getOutcomeFact, getComp
    TDA_obj <- dfToDistance(TDA_obj, distMethod = "euclidean")
    TDA_obj <- dfToProjection(TDA_obj, "UMAP", nComp = 2,
                              umapNNeigh = 25, umapMinDist = 0.3,
                              showPlot = FALSE)
    df_plot <- as.data.frame(cbind(getOutcomeFact(TDA_obj),
                                   getComp(TDA_obj)),
                             stringAsFactor = TRUE)


    # --- Topological Data Analysis [] ---
    # Key functions: mapperCore, getDfMapper
    TDA_obj <- mapperCore(TDA_obj, nBins = 15, overlap = 0.3,
                          clustMeth = "kmeans")
    mapper_df <- getDfMapper(TDA_obj)


    # --- Jaccard Similarity Analysis [] ---
    # Key functions: jaccardMatrix, getJacc
    TDA_obj <- jaccardMatrix(TDA_obj)
    jacc_mat <- getJacc(TDA_obj)


    # --- Enrichment and Network Analysis [] ---
    # Key functions: tdaDfEnrichment, checkNetEntropy, checkScaleFreeModel
    TDA_obj <- tdaDfEnrichment(TDA_obj,
                               cbind(getScaledData(TDA_obj),
                                     getOutcome(TDA_obj)))
    entropy <- checkNetEntropy(getNodeDataMat(TDA_obj)[, "zone"])
    netModel <- checkScaleFreeModel(TDA_obj, showPlot = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_piuma_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_piuma_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_piuma_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PIUMA:", paste0("    piuma: ", packageVersion("PIUMA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_piuma_results.csv
    touch ${prefix}_piuma_output.rds
    echo "BIOC_PIUMA:" > versions.yml
    echo "    piuma: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PIUMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PIUMA(ch_input)

    emit:
    results  = BIOC_PIUMA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PIUMA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PIUMA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PIUMA.out.versions  // channel: path(versions.yml)
}
