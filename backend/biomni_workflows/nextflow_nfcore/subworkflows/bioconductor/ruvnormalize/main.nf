#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RUVnormalize — naive_ruv2
// Remove unwanted variation from gene expression data using negative control genes with or without shrinkage.
// Input: expression_matrix.csv, negative_controls.txt
// Container: quay.io/biocontainers/bioconductor-ruvnormalize:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RUVnormalize
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read user input files
//  * 2. [Visualization & Output] Center the gene expression matrix
//  * 3. [Visualization & Output] Run naive RUV-2 without shrinkage
//  * 4. [Visualization & Output] Visualize the corrected data using SVD/PCA plotting

nextflow.enable.dsl = 2

process BIOC_RUVNORMALIZE_NAIVE_RUV2 {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("RUVnormalize")
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
    library(RUVnormalize)
    
    # --- Read user input files ---
    Y <- as.matrix(read.csv("expression_matrix.csv", row.names=1, check.names=FALSE))
    
    # Read negative controls
    controls <- readLines("negative_controls.txt")
    # Determine if controls are indices or names
    cIdx <- suppressWarnings(as.integer(controls))
    if (any(is.na(cIdx)) || length(cIdx) == 0) {
      cIdx <- which(colnames(Y) %in% controls)
    }
    
    # --- Center the gene expression matrix ---
    Y <- scale(Y, scale=FALSE)
    
    # Define dimensions
    m <- nrow(Y)
    n <- ncol(Y)
    
    # --- Run naive RUV-2 without shrinkage ---
    k <- min(20, m)
    nu <- 0
    nsY <- naiveRandRUV(Y, cIdx, nu.coeff=0, k=k)
    
    # Run naive RUV-2 with shrinkage
    k <- m
    nu.coeff <- 1e-3
    nY <- naiveRandRUV(Y, cIdx, nu.coeff=nu.coeff, k=k)
    
    # --- Visualize the corrected data using SVD/PCA plotting ---
    nKeep <- min(1260, n)
    sdY <- apply(nY, 2, sd)
    ssd <- sort(sdY, decreasing=TRUE, index.return=TRUE)\$ix
    
    # Prepare annotations for plotting
    annot <- matrix("sample", nrow=nrow(Y), ncol=1)
    colnames(annot) <- "group"
    plAnnots <- list("group"="categorical")
    lab.and.region <- rownames(Y)
    if (is.null(lab.and.region)) {
      lab.and.region <- as.character(1:nrow(Y))
    }
    gender.col <- c("sample" = "blue")
    
    # Plot to PDF
    pdf("svd_plot_corrected.pdf")
    svdRes2 <- svdPlot(nY[, ssd[1:nKeep], drop=FALSE], 
                         annot=annot, 
                         labels=lab.and.region, 
                         svdRes=NULL, 
                         plAnnots=plAnnots,                     
                         kColors=gender.col, file=NULL)
    dev.off()
    
    # Write outputs
    write.csv(nsY, "corrected_expression_noshrink.csv", row.names=TRUE)
    write.csv(nY, "corrected_expression_shrink.csv", row.names=TRUE)
    saveRDS(svdRes2, "svd_results.rds")

    writeLines(c(
        '"BIOC_RUVNORMALIZE_NAIVE_RUV2":',
        paste0('    RUVnormalize: ', as.character(packageVersion('RUVnormalize')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_naive_ruv2.csv versions.yml
    """
}

workflow BIOC_RUVNORMALIZE_NAIVE_RUV2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, negative_controls.txt ] ]

    main:
    BIOC_RUVNORMALIZE_NAIVE_RUV2(ch_input)

    emit:
    tables   = BIOC_RUVNORMALIZE_NAIVE_RUV2.out.tables
    plots    = BIOC_RUVNORMALIZE_NAIVE_RUV2.out.plots
    objects  = BIOC_RUVNORMALIZE_NAIVE_RUV2.out.objects
    versions = BIOC_RUVNORMALIZE_NAIVE_RUV2.out.versions
}
