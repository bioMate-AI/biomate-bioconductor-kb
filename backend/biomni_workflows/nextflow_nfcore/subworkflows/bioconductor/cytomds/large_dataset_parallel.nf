#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CytoMDS — large_dataset_parallel
// Calculate pairwise sample distances for large datasets by dynamically loading samples from disk and parallelizing computations to save memory and time.
// Input: fileNames
// Container: quay.io/biocontainers/bioconductor-cytomds:1.6.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, CytoMDS, flowCore, ggplot2
// Visualizations: MDS plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Set up parallel execution parameters using BiocParallel::SnowParam
//  * 2. [Core Analysis] Compute pairwise EMD distances using pairwiseEMDDist with a custom loading function and parallel backend

nextflow.enable.dsl = 2

process BIOC_CYTOMDS_LARGE_DATASET_PARALLEL {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("CytoMDS", "flowCore", "BiocParallel", "ggplot2")
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
    library(CytoMDS)
    library(flowCore)
    library(BiocParallel)
    library(ggplot2)
    
    # 1. Identify input files from the working directory
    if (file.exists("fileNames.rds")) {
        fileNames <- readRDS("fileNames.rds")
    } else {
        fileNames <- list.files(pattern = "\\\\.rds\$", full.names = TRUE)
        # Exclude fileNames.rds itself if it exists in the list
        fileNames <- fileNames[fileNames != "./fileNames.rds" & fileNames != "fileNames.rds"]
    }
    
    if (length(fileNames) == 0) {
        stop("No RDS files found in the working directory. Please provide transformed sample RDS files.")
    }
    
    nSample <- length(fileNames)
    
    # Read the first file to extract channel and marker information dynamically
    first_ff <- readRDS(fileNames[1])
    chLabels <- colnames(first_ff)
    
    # Ensure chMarkers has the same length and corresponds to chLabels
    chMarkers <- tryCatch({
        m <- flowCore::markernames(first_ff)
        m_aligned <- chLabels
        names(m_aligned) <- chLabels
        common <- intersect(names(m), chLabels)
        m_aligned[common] <- m[common]
        unname(m_aligned)
    }, error = function(e) {
        chLabels
    })
    
    # Stage 1: Set up parallel execution parameters using BiocParallel::SnowParam
    bp <- BiocParallel::SnowParam(
        stop.on.error = FALSE,
        progressbar = TRUE)
    
    # Stage 2: Compute pairwise EMD distances using pairwiseEMDDist with a custom loading function and parallel backend
    pwDistLast <- suppressWarnings(pairwiseEMDDist(
        x = nSample,
        channels = chMarkers,
        loadExprMatrixFUN  = function(exprMatrixIndex, files, channels, markers){
            ff <- readRDS(file = files[exprMatrixIndex ])
            exprMat <- flowCore::exprs(ff)[, channels, drop = FALSE]
            colnames(exprMat) <- markers
            exprMat
        },
        loadExprMatrixFUNArgs = list(
            files = fileNames, 
            channels = chLabels,
            markers = chMarkers),
        BPPARAM = bp))
    
    # Stage 3: Save meaningful results to disk
    # Save the distance object
    saveRDS(pwDistLast, "pairwise_emd_distances.rds")
    
    # Save the distance matrix as a CSV table
    pwDistMatrix <- as.matrix(pwDistLast)
    write.csv(pwDistMatrix, "pairwise_emd_distances.csv", row.names = TRUE)
    
    # Compute MDS projection for downstream visualization
    mdsObj <- computeMetricMDS(pwDistLast, seed = 0)
    saveRDS(mdsObj, "mds_projection.rds")
    
    # Plot and save the MDS projection
    pdf("mds_projection_plot.pdf", width = 7, height = 7)
    p_mds <- ggplotSampleMDS(mdsObj)
    print(p_mds)
    dev.off()
    
    # Plot and save the Shepard diagram for quality control
    pdf("shepard_diagram.pdf", width = 7, height = 7)
    p_shep <- ggplotSampleMDSShepard(mdsObj)
    print(p_shep)
    dev.off()

    writeLines(c(
        '"BIOC_CYTOMDS_LARGE_DATASET_PARALLEL":',
        paste0('    CytoMDS: ', as.character(packageVersion('CytoMDS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_large_dataset_parallel.csv versions.yml
    """
}

workflow BIOC_CYTOMDS_LARGE_DATASET_PARALLEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fileNames ] ]

    main:
    BIOC_CYTOMDS_LARGE_DATASET_PARALLEL(ch_input)

    emit:
    tables   = BIOC_CYTOMDS_LARGE_DATASET_PARALLEL.out.tables
    plots    = BIOC_CYTOMDS_LARGE_DATASET_PARALLEL.out.plots
    objects  = BIOC_CYTOMDS_LARGE_DATASET_PARALLEL.out.objects
    versions = BIOC_CYTOMDS_LARGE_DATASET_PARALLEL.out.versions
}
