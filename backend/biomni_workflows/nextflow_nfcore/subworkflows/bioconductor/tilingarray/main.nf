#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tilingArray — piecewise_segmentation
// Fit a piecewise constant curve to sequential genomic data and select the optimal number of segments using AIC or BIC.
// Input: intensity_matrix.txt
// Container: quay.io/biocontainers/bioconductor-tilingarray:1.88.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: tilingArray
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run segmentation using the segment function with specified maxk and maxseg constraints
//  * 2. [Visualization & Output] Plot penalized log-likelihoods using plotPenLL
//  * 3. [Core Analysis] Identify the optimal number of segments using logLik with AIC or BIC penalties

nextflow.enable.dsl = 2

process BIOC_TILINGARRAY_PIECEWISE_SEGMENTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("tilingArray")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library("tilingArray")
    
    # -------------------------------------------------------------------------
    # 1. Read User Input
    # -------------------------------------------------------------------------
    # The pipeline reads 'intensity_matrix.txt' from the working directory.
    # This file is expected to be a matrix of normalized intensity values
    # where rows represent genomic positions and columns represent replicates/samples.
    if (!file.exists("intensity_matrix.txt")) {
      stop("Error: 'intensity_matrix.txt' not found in the working directory.")
    }
    
    intensity_matrix <- as.matrix(read.table("intensity_matrix.txt", header = TRUE))
    
    # Construct the gd list containing the data matrix in gd\$x
    gd <- list(x = intensity_matrix)
    
    # -------------------------------------------------------------------------
    # 2. Define Parameters Dynamically based on Input Size
    # -------------------------------------------------------------------------
    lenx <- nrow(gd\$x)
    if (lenx < 3) {
      stop("Error: Input intensity matrix must have at least 3 rows (genomic positions) for segmentation.")
    }
    
    # Determine a safe nrSeg (fixed to avoid linear scaling with input size)
    nrSeg <- 22
    while (as.integer(nrSeg * 2.5) >= lenx && nrSeg > 1) {
      nrSeg <- nrSeg - 1
    }
    
    # Determine safe maxseg and maxk constraints
    maxseg <- 12
    if (maxseg >= lenx) {
      maxseg <- lenx - 1
    }
    if (maxseg < 2) {
      maxseg <- 2
    }
    
    maxk <- 500
    if (maxk > lenx) {
      maxk <- lenx
    }
    
    # -------------------------------------------------------------------------
    # 3. Run Documented Segmentation Workflow
    # -------------------------------------------------------------------------
    
    # Stage 1: Run segmentation using the segment function with specified maxk and maxseg constraints
    seg  = segment(gd\$x, maxk=maxk, maxseg=maxseg)
    
    # Run segmentation for model selection
    s = segment(gd\$x, maxk=maxk, maxseg=as.integer(nrSeg * 2.5))
    
    # Stage 2: Plot penalized log-likelihoods using plotPenLL
    pdf("penalized_log_likelihood.pdf", width = 7, height = 6)
    plotPenLL(s)
    dev.off()
    
    # Stage 3: Identify the optimal number of segments using logLik with AIC or BIC penalties
    aic_opt <- which.max(logLik(s, penalty="AIC"))
    bic_opt <- which.max(logLik(s, penalty="BIC"))
    
    # -------------------------------------------------------------------------
    # 4. Save Outputs
    # -------------------------------------------------------------------------
    # Save the segmentation objects
    saveRDS(seg, "segmentation_constrained.rds")
    saveRDS(s, "segmentation_model_selection.rds")
    
    # Save the optimal model selection results
    results <- data.frame(
      Metric = c("AIC_Optimal_Segments", "BIC_Optimal_Segments"),
      Value = c(aic_opt, bic_opt)
    )
    write.csv(results, "optimal_segments.csv", row.names = FALSE)
    
    # Save the breakpoints of the BIC-optimal model if available
    if (bic_opt <= length(s@breakpoints) && bic_opt > 0) {
      bp_bic <- s@breakpoints[[bic_opt]]
      write.csv(as.data.frame(bp_bic), "breakpoints_bic_optimal.csv", row.names = FALSE)
    }
    
    cat("Pipeline completed successfully.\n")
    cat("Outputs saved:\n")
    cat(" - penalized_log_likelihood.pdf\n")
    cat(" - segmentation_constrained.rds\n")
    cat(" - segmentation_model_selection.rds\n")
    cat(" - optimal_segments.csv\n")
    cat(" - breakpoints_bic_optimal.csv\n")

    writeLines(c(
        '"BIOC_TILINGARRAY_PIECEWISE_SEGMENTATION":',
        paste0('    tilingArray: ', as.character(packageVersion('tilingArray')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_piecewise_segmentation.csv versions.yml
    """
}

workflow BIOC_TILINGARRAY_PIECEWISE_SEGMENTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ intensity_matrix.txt ] ]

    main:
    BIOC_TILINGARRAY_PIECEWISE_SEGMENTATION(ch_input)

    emit:
    tables   = BIOC_TILINGARRAY_PIECEWISE_SEGMENTATION.out.tables
    plots    = BIOC_TILINGARRAY_PIECEWISE_SEGMENTATION.out.plots
    objects  = BIOC_TILINGARRAY_PIECEWISE_SEGMENTATION.out.objects
    versions = BIOC_TILINGARRAY_PIECEWISE_SEGMENTATION.out.versions
}
