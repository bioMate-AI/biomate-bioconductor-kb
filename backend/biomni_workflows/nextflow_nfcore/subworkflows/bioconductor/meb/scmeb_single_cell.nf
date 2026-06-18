#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MEB — scmeb_single_cell
// Identify differentially expressed genes in single-cell RNA-seq data without prior cell clustering.
// Input: sce, stable_idx
// Container: quay.io/biocontainers/bioconductor-meb:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MEB, SingleCellExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Train the scMEB model using scMEB
//  * 2. [Core Analysis] Predict DEG status using predict on the trained model and PCA data
//  * 3. [Core Analysis] Extract distance metrics to rank genes by DEG likelihood

nextflow.enable.dsl = 2

process BIOC_MEB_SCMEB_SINGLE_CELL {
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
    .bm_deps <- c("MEB")
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
    library(MEB)
    
    # 1. Read User Inputs
    if (!file.exists("sce.rds")) {
      stop("Error: 'sce.rds' (SingleCellExperiment object) is missing from the working directory.")
    }
    if (!file.exists("stable_idx.rds")) {
      stop("Error: 'stable_idx.rds' (vector of stable gene names/indices) is missing from the working directory.")
    }
    
    sce <- readRDS("sce.rds")
    stable_idx <- readRDS("stable_idx.rds")
    
    # 2. Train the scMEB model
    # Documented call adapted to use the loaded 'sce' and 'stable_idx'
    sim_scRNA <- scMEB(
      sce = sce, 
      stable_idx = stable_idx, 
      filtered = TRUE, 
      gamma = seq(1e-04, 0.001, 1e-05), 
      nu = 0.01, 
      reject_rate = 0.1
    )
    
    # 3. Predict DEG status using predict on the trained model and PCA data
    sim_scRNA_pred <- predict(sim_scRNA\$model, sim_scRNA\$dat_pca)
    
    # Print summaries to standard output
    cat("--- Prediction Summary ---\n")
    print(summary(sim_scRNA_pred))
    
    cat("\n--- Distance Threshold Table (dist > 0) ---\n")
    print(table(sim_scRNA\$dist > 0))
    
    # 4. Extract distance metrics to rank genes by DEG likelihood
    sim_scRNA_dist <- data.frame(
      Gene = rownames(sce),
      Distance = sim_scRNA\$dist
    )
    
    cat("\n--- Head of Distance Data Frame ---\n")
    print(head(sim_scRNA_dist))
    
    # 5. Save Outputs
    # Save the full model object
    saveRDS(sim_scRNA, "scmeb_model_output.rds")
    
    # Save predictions
    saveRDS(sim_scRNA_pred, "scmeb_predictions.rds")
    
    # Save distance metrics as CSV
    write.csv(sim_scRNA_dist, "scmeb_gene_distances.csv", row.names = FALSE)
    
    # Generate a PDF plot of the distances
    pdf("scmeb_distances_distribution.pdf", width = 7, height = 5)
    hist(
      sim_scRNA\$dist, 
      breaks = 50, 
      col = "skyblue", 
      border = "white",
      main = "Distribution of scMEB Distances", 
      xlab = "Distance (Larger = More likely DEG)"
    )
    abline(v = 0, col = "red", lty = 2, lwd = 2)
    dev.off()
    
    cat("\nPipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_MEB_SCMEB_SINGLE_CELL":',
        paste0('    MEB: ', as.character(packageVersion('MEB')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scmeb_single_cell.csv versions.yml
    """
}

workflow BIOC_MEB_SCMEB_SINGLE_CELL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce, stable_idx ] ]

    main:
    BIOC_MEB_SCMEB_SINGLE_CELL(ch_input)

    emit:
    tables   = BIOC_MEB_SCMEB_SINGLE_CELL.out.tables
    plots    = BIOC_MEB_SCMEB_SINGLE_CELL.out.plots
    objects  = BIOC_MEB_SCMEB_SINGLE_CELL.out.objects
    versions = BIOC_MEB_SCMEB_SINGLE_CELL.out.versions
}
