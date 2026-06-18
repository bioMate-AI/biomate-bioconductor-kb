#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nempi — unsupervised_perturbation_inference
// Infer unobserved perturbations and reconstruct causal networks from gene expression data with partially missing perturbation labels.
// Input: data
// Container: quay.io/biocontainers/bioconductor-nempi:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mnem, nempi
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run network-based perturbation inference using nempi
//  * 2. [Core Analysis] Evaluate inference accuracy using pifit
//  * 3. [Visualization & Output] Plot the inferred perturbation profiles and network
//  * 4. [Core Analysis] Compute the final transitive-closed perturbation matrix Omega

nextflow.enable.dsl = 2

process BIOC_NEMPI_UNSUPERVISED_PERTURBATION_INFERENCE {
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
    .bm_deps <- c("nempi", "mnem")
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
    library(nempi)
    library(mnem)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input
    # -----------------------------------------------------------------------------
    # Read the gene expression log odds matrix 'data' from the working directory.
    # We support both RDS and CSV formats.
    if (file.exists("data.rds")) {
      data <- readRDS("data.rds")
    } else if (file.exists("data.csv")) {
      data <- as.matrix(read.csv("data.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Required input file 'data.rds' or 'data.csv' not found in the working directory.")
    }
    
    # Read 'simmini' (ground truth simulation object) if available.
    # If not available, we skip pifit evaluation.
    if (file.exists("simmini.rds")) {
      simmini <- readRDS("simmini.rds")
    } else {
      warning("simmini.rds not found. Skipping pifit evaluation.")
      simmini <- NULL
    }
    
    # -----------------------------------------------------------------------------
    # Stage 1: Run network-based perturbation inference using nempi
    # -----------------------------------------------------------------------------
    res <- nempi(data)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Evaluate inference accuracy using pifit
    # -----------------------------------------------------------------------------
    if (!is.null(simmini)) {
      fit <- pifit(res, simmini, data)
      print(fit\$auc)
    }
    
    # -----------------------------------------------------------------------------
    # Stage 3: Plot the inferred perturbation profiles and network
    # -----------------------------------------------------------------------------
    col <- rgb(seq(0,1,length.out=10),seq(1,0,length.out=10),
               seq(1,0,length.out=10))
    
    pdf("inferred_perturbation_plot.pdf", width = 10, height = 8)
    plot(res,heatlist=list(col="RdBu"),barlist=list(col=col))
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 4: Compute the final transitive-closed perturbation matrix Omega
    # -----------------------------------------------------------------------------
    Omega <- t(mnem::transitive.closure(res\$res\$adj))%*%res\$Gamma
    
    # -----------------------------------------------------------------------------
    # Stage 5: Save meaningful results to files
    # -----------------------------------------------------------------------------
    saveRDS(res, "nempi_results.rds")
    if (!is.null(simmini)) {
      saveRDS(fit, "pifit_results.rds")
      writeLines(as.character(fit\$auc), "auc.txt")
    }
    write.csv(Omega, "omega_matrix.csv", row.names = TRUE)
    saveRDS(Omega, "omega_matrix.rds")
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_NEMPI_UNSUPERVISED_PERTURBATION_INFERENCE":',
        paste0('    nempi: ', as.character(packageVersion('nempi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unsupervised_perturbation_inference.csv versions.yml
    """
}

workflow BIOC_NEMPI_UNSUPERVISED_PERTURBATION_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data ] ]

    main:
    BIOC_NEMPI_UNSUPERVISED_PERTURBATION_INFERENCE(ch_input)

    emit:
    tables   = BIOC_NEMPI_UNSUPERVISED_PERTURBATION_INFERENCE.out.tables
    plots    = BIOC_NEMPI_UNSUPERVISED_PERTURBATION_INFERENCE.out.plots
    objects  = BIOC_NEMPI_UNSUPERVISED_PERTURBATION_INFERENCE.out.objects
    versions = BIOC_NEMPI_UNSUPERVISED_PERTURBATION_INFERENCE.out.versions
}
