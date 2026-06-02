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
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: tempdir, normalyzer
    library(NormalyzerDE)
    outDir <- tempdir()
    designFp <- system.file(package="NormalyzerDE", "extdata", "tiny_design.tsv")
    dataFp <- system.file(package="NormalyzerDE", "extdata", "tiny_data.tsv")
    # --- Code Block 4 [] ---
    # Key functions: normalyzerDE
    normMatrixPath <- paste(outDir, "vignette_run/CycLoess-normalized.txt", sep="/")
    # --- Code Block 7 [] ---
    # Key functions: SummarizedExperiment, normalyzer
    dataMatrix <- read.table(dataFp, sep="\t", header = TRUE)
    designMatrix <- read.table(designFp, sep="\t", header = TRUE)
    designMatrix$sample <- as.character(designMatrix$sample)
    dataOnly <- dataMatrix[, designMatrix$sample]
    annotOnly <- dataMatrix[, !(colnames(dataMatrix) %in% designMatrix$sample)]
    # --- Code Block 10 [] ---
    # Key functions: csv
    fullDf <- read.csv(dataFp, sep="\t")
    designDf <- read.csv(designFp, sep="\t")
    head(fullDf, 1)
    # --- Code Block 11 [] ---
    # Key functions: typeof
    sampleNames <- as.character(designDf$sample)
    typeof(sampleNames)
    # --- Code Block 13 [] ---
    # Key functions: normalizeCyclicLoess

    # --- Code Block 14 [] ---
    # Key functions: getRTNormalizedMatrix
    rtNormMat <- getRTNormalizedMatrix(dataMat,
                                       retentionTimes,
                                       performCyclicLoessNormalization,
                                       stepSizeMinutes=1,
                                       windowMinCount=100)
    # --- Code Block 15 [] ---
    # Key functions: performCyclicLoessNormalization
    globalNormMat <- performCyclicLoessNormalization(dataMat)
    dim(rtNormMat)

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
