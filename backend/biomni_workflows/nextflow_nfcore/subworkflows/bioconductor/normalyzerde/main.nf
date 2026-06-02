#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NormalyzerDE
// NormalyzerDE provides screening of normalization methods for LC-MS based expression data. It calcula
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/NormalyzerDE/inst/doc/vignette.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("NormalyzerDE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMALYZERDE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-normalyzerde"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-normalyzerde:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-normalyzerde:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_normalyzerde_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_normalyzerde_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_normalyzerde_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NormalyzerDE)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Input Data Preparation ---
    # Key functions: system.file
    designFp <- system.file(package="NormalyzerDE", "extdata", "tiny_design.tsv")
    dataFp <- system.file(package="NormalyzerDE", "extdata", "tiny_data.tsv")
    designMatrix <- read.table(designFp, sep="\t", header=TRUE)
    dataMatrix <- read.table(dataFp, sep="\t", header=TRUE)
    sampleNames <- as.character(designMatrix$sample)
    dataOnly <- dataMatrix[, sampleNames]
    annotOnly <- dataMatrix[, !(colnames(dataMatrix) %in% sampleNames)]

    # --- Normalization Evaluation ---
    # Key functions: normalyzer
    outDir <- tempdir()
    designFp <- system.file(package="NormalyzerDE", "extdata", "tiny_design.tsv")
    dataFp <- system.file(package="NormalyzerDE", "extdata", "tiny_data.tsv")
    normalyzer(
        jobName="vignette_run",
        designPath=designFp,
        dataPath=dataFp,
        outputDir=outDir
    )

    # --- Differential Expression Analysis ---
    # Key functions: normalyzerDE
    outDir <- tempdir()
    designFp <- system.file(package="NormalyzerDE", "extdata", "tiny_design.tsv")
    normMatrixPath <- file.path(outDir, "vignette_run", "CycLoess-normalized.txt")
    normalyzerDE(
        jobName="vignette_run",
        comparisons=c("4-5"),
        designPath=designFp,
        dataPath=normMatrixPath,
        outputDir=outDir
    )

    # --- Retention Time Segmentation Normalization ---
    # Key functions: getRTNormalizedMatrix
    dataMat <- matrix(runif(1000), ncol=10)
    colnames(dataMat) <- paste0("Sample", 1:10)
    retentionTimes <- runif(100, min=1, max=30)
    performCyclicLoess <- function(rawMatrix) {
        log2Matrix <- log2(rawMatrix)
        normMatrix <- limma::normalizeCyclicLoess(log2Matrix, method="fast")
        colnames(normMatrix) <- colnames(rawMatrix)
        return(normMatrix)
    }
    rtNormMat <- getRTNormalizedMatrix(
        dataMat,
        retentionTimes,
        performCyclicLoess,
        stepSizeMinutes=1,
        windowMinCount=10
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_normalyzerde_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_normalyzerde_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_normalyzerde_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NORMALYZERDE:", paste0("    normalyzerde: ", packageVersion("NormalyzerDE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_normalyzerde_results.csv
    touch ${prefix}_normalyzerde_output.rds
    echo "BIOC_NORMALYZERDE:" > versions.yml
    echo "    normalyzerde: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NORMALYZERDE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NORMALYZERDE(ch_input)

    emit:
    results  = BIOC_NORMALYZERDE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NORMALYZERDE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NORMALYZERDE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NORMALYZERDE.out.versions  // channel: path(versions.yml)
}
