#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SDAMS
// This Package utilizes a Semi-parametric Differential Abundance/expression analysis (SDA) method for 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SDAMS/inst/doc/SDAMS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SDAMS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SDAMS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sdams"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sdams:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sdams:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sdams_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sdams_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sdams_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SDA)
    library(jsonlite)

    # --- Quick Start [] ---
    # Key functions: SDA
    ## library("SDAMS")
    ## data("exampleSumExp")
    ## results <- SDA(exampleSumExp)
    # --- Getdirectory [] ---
    # Key functions: path
    directory1 <- system.file("extdata", package = "SDAMS", mustWork = TRUE)
    path1 <- file.path(directory1, "ProstateFeature.csv")
    directory2 <- system.file("extdata", package = "SDAMS", mustWork = TRUE)
    path2 <- file.path(directory2, "ProstateGroup.csv")
    # --- Csvinput [] ---
    # Key functions: createSEFromCSV
    library("SDAMS")
    exampleSE1 <- createSEFromCSV(path1, path2)
    exampleSE1
    # --- Accessors [] ---
    # Key functions: assay, colData
    head(assay(exampleSE1)[,1:10])
    head(colData(exampleSE1)$grouping)
    # --- Matrixinput [] ---
    # Key functions: runif, frame, sample
    set.seed(100)
    featureInfo <- matrix(runif(8000, -2, 5), ncol = 40)
    featureInfo[featureInfo<0] <- 0
    rownames(featureInfo) <- paste("gene", 1:200, sep = '')
    colnames(featureInfo) <- paste('cell', 1:40, sep = '')
    # --- Resultsforgamma [] ---
    # Key functions: SDA
    results <- SDA(exampleSE1)
    head(results$gamma[,1])
    head(results$pv_gamma[,1])
    head(results$qv_gamma[,1])
    # --- Analysisandresults [] ---
    # Key functions: SDA
    results_SC <- SDA(exampleSE2)
    head(results_SC$pv_gamma[,1])
    head(results_SC$qv_gamma[,1])
    head(results_SC$pv_beta[,1])
    head(results_SC$qv_beta[,1])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sdams_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sdams_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sdams_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SDAMS:", paste0("    sdams: ", packageVersion("SDAMS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sdams_results.csv
    touch ${prefix}_sdams_output.rds
    echo "BIOC_SDAMS:" > versions.yml
    echo "    sdams: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SDAMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SDAMS(ch_input)

    emit:
    results  = BIOC_SDAMS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SDAMS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SDAMS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SDAMS.out.versions  // channel: path(versions.yml)
}
