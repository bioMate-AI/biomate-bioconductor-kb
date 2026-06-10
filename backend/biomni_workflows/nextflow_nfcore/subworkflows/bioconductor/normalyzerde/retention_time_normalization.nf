#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normalyzerde — retention_time_normalization
// Apply retention-time segmented or layered/smoothed normalization directly to a raw data matrix.
// Input: tiny_data.tsv, tiny_design.tsv
// Container: quay.io/biocontainers/bioconductor-normalyzerde:1.28.0--r45hdfd78af_0
// R packages: NormalyzerDE
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMALYZERDE_RETENTION_TIME_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-normalyzerde:1.28.0--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("NormalyzerDE")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(NormalyzerDE)
    
    # Define input file paths
    dataFp <- "tiny_data.tsv"
    designFp <- "tiny_design.tsv"
    
    # Read input files
    fullDf <- read.csv(dataFp, sep="\t")
    designDf <- read.csv(designFp, sep="\t")
    
    # Extract sample names, data matrix, and retention times
    sampleNames <- as.character(designDf\$sample)
    dataMat <- as.matrix(fullDf[, sampleNames])
    retentionTimes <- fullDf\$Average.RT
    
    # Define the normalization wrapper function
    performCyclicLoessNormalization <- function(rawMatrix) {
        log2Matrix <- log2(rawMatrix)
        normMatrix <- limma::normalizeCyclicLoess(log2Matrix, method="fast")
        colnames(normMatrix) <- colnames(rawMatrix)
        normMatrix
    }
    
    # Perform retention-time based normalization
    rtNormMat <- getRTNormalizedMatrix(dataMat, 
                                       retentionTimes, 
                                       performCyclicLoessNormalization, 
                                       stepSizeMinutes=1, 
                                       windowMinCount=100)
    
    # Perform layered/smoothed retention-time based normalization
    layeredRtNormMat <- getSmoothedRTNormalizedMatrix(
        dataMat, 
        retentionTimes, 
        performCyclicLoessNormalization, 
        stepSizeMinutes=1, 
        windowMinCount=100, 
        windowShifts=3, 
        mergeMethod="mean")
    
    # Write outputs to files
    write.table(rtNormMat, file="rt_normalized_matrix.tsv", sep="\t", col.names=NA, quote=FALSE)
    write.table(layeredRtNormMat, file="layered_rt_normalized_matrix.tsv", sep="\t", col.names=NA, quote=FALSE)
    saveRDS(rtNormMat, file="rt_normalized_matrix.rds")
    saveRDS(layeredRtNormMat, file="layered_rt_normalized_matrix.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NORMALYZERDE_RETENTION_TIME_NORMALIZATION":
        normalyzerde: \$(Rscript -e 'cat(as.character(packageVersion("normalyzerde")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_retention_time_normalization.csv versions.yml
    """
}

workflow BIOC_NORMALYZERDE_RETENTION_TIME_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tiny_data.tsv, tiny_design.tsv ] ]

    main:
    BIOC_NORMALYZERDE_RETENTION_TIME_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_NORMALYZERDE_RETENTION_TIME_NORMALIZATION.out.tables
    plots    = BIOC_NORMALYZERDE_RETENTION_TIME_NORMALIZATION.out.plots
    objects  = BIOC_NORMALYZERDE_RETENTION_TIME_NORMALIZATION.out.objects
    versions = BIOC_NORMALYZERDE_RETENTION_TIME_NORMALIZATION.out.versions
}
