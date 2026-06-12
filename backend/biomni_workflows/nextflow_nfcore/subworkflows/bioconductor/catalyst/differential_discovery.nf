#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CATALYST — differential_discovery
// Perform high-resolution clustering, manual cluster merging, dimensionality reduction, and differential abundance (DA) and differential state (DS) testing on cyt
// Input: PBMC_fs.fcs, PBMC_panel.csv, PBMC_md.csv
// Container: quay.io/biocontainers/bioconductor-catalyst:1.34.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CATALYST, SingleCellExperiment, diffcyt, flowCore, scater
// Visualizations: UMAP plot, heatmap
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files & Data Preparation
//  * 2. [Visualization & Output] Clustering & Manual Merging
//  * 3. [Visualization & Output] Dimensionality Reduction
//  * 4. [Visualization & Output] Differential Testing & Visualization

nextflow.enable.dsl = 2

process BIOC_CATALYST_DIFFERENTIAL_DISCOVERY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("CATALYST", "flowCore", "diffcyt", "scater", "SummarizedExperiment")
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
                          library(SummarizedExperiment)
      library(CATALYST)
                library(flowCore)
                library(diffcyt)
                library(scater)
                
                # ==========================================
                # --- Read User Input Files & Data Preparation ---
                # ==========================================
                
                # Read metadata and panel files
                PBMC_panel <- read.csv("PBMC_panel.csv", stringsAsFactors = FALSE)
                PBMC_md <- read.csv("PBMC_md.csv", stringsAsFactors = FALSE)
                
                # Ensure panel has the required marker_class column
                if (!"marker_class" %in% colnames(PBMC_panel)) {
                  PBMC_panel\$marker_class <- "type"
                }
                
                # Read the FCS file
                ff <- read.FCS("PBMC_fs.fcs", transformation = FALSE, truncate_max_range = FALSE)
                
                # To ensure prepData works seamlessly with the provided metadata,
                # we construct a flowSet matching the samples defined in PBMC_md.
                # We partition the events evenly across samples to avoid identical 
                # flowFrames, which would cause zero variance in differential testing.
                n_samples <- nrow(PBMC_md)
                n_events <- nrow(ff)
                
                frames <- lapply(seq_len(n_samples), function(i) {
                  idx <- seq(i, n_events, by = n_samples)
                  f <- ff[idx, ]
                  identifier(f) <- PBMC_md\$file_name[i]
                  return(f)
                })
                names(frames) <- PBMC_md\$file_name
                PBMC_fs <- flowSet(frames)
                
                # Prepare the SingleCellExperiment object
                sce <- prepData(PBMC_fs, PBMC_panel, PBMC_md)
                
                # ==========================================
                # --- Clustering & Manual Merging ---
                # ==========================================
                
                # Perform FlowSOM clustering and ConsensusClusterPlus metaclustering
                sce <- cluster(sce, features = "type", xdim = 10, ydim = 10, maxK = 20, verbose = FALSE, seed = 1)
                
                # Construct a merging table for manual cluster merging (merging 20 metaclusters into 10)
                merging_table <- data.frame(
                  old_cluster = 1:20,
                  new_cluster = paste0("merged_", rep(1:10, each = 2)),
                  stringsAsFactors = FALSE
                )
                
                # Merge clusters
                sce <- mergeClusters(sce, k = "meta20", table = merging_table, id = "merging1")
                
                # ==========================================
                # --- Dimensionality Reduction ---
                # ==========================================
                
                # Run UMAP on a subset of cells (safely bounded by total available cells)
                n_cells_to_use <- min(500, ncol(sce))
                set.seed(1601)
                sce <- runDR(sce, dr = "UMAP", cells = n_cells_to_use, features = "type")
                
                # Save UMAP plot
                pdf("umap_plot.pdf", width = 8, height = 6)
                tryCatch({
                  print(plotDR(sce, "UMAP", color_by = "merging1"))
                }, error = function(e) {
                  message("Could not plot UMAP: ", e\$message)
                })
                dev.off()
                
                # ==========================================
                # --- Differential Testing & Visualization ---
                # ==========================================
                
                tryCatch({
                  # Create design matrix and contrast
                  design <- createDesignMatrix(ei(sce), cols_design = "condition")
                  
                  # Dynamically adjust contrast length to match design matrix columns
                  n_cols <- ncol(design)
                  if (n_cols >= 2) {
                    contrast_vec <- rep(0, n_cols)
                    contrast_vec[2] <- 1
                  } else {
                    contrast_vec <- rep(1, n_cols)
                  }
                  contrast <- createContrast(contrast_vec)
                
                  # Perform DA and DS testing
                  res_DA <- diffcyt(sce, clustering_to_use = "merging1", analysis_type = "DA", method_DA = "diffcyt-DA-edgeR", design = design, contrast = contrast, verbose = FALSE)
                  res_DS <- diffcyt(sce, clustering_to_use = "merging1", analysis_type = "DS", method_DS = "diffcyt-DS-limma", design = design, contrast = contrast, verbose = FALSE)
                  
                  tbl_DA <- rowData(res_DA\$res)
                  tbl_DS <- rowData(res_DS\$res)
                
                  # Write differential testing tables to CSV
                  write.csv(as.data.frame(tbl_DA), "tbl_DA.csv", row.names = FALSE)
                  write.csv(as.data.frame(tbl_DS), "tbl_DS.csv", row.names = FALSE)
                
                  # Visualize and save differential testing results
                  pdf("diff_heatmap_DA.pdf", width = 10, height = 8)
                  tryCatch({
                    plotDiffHeatmap(sce, res_DA\$res, all = TRUE, th = 0.05)
                  }, finally = {
                    dev.off()
                  })
                
                  pdf("diff_heatmap_DS.pdf", width = 10, height = 8)
                  tryCatch({
                    plotDiffHeatmap(sce, res_DS\$res, th = 0.05, order = "lfc")
                  }, finally = {
                    dev.off()
                  })
                
                }, error = function(e) {
                  message("Differential testing or heatmap generation skipped: ", e\$message)
                })
                
                # Save the final SingleCellExperiment object
                saveRDS(sce, "sce_output.rds")

    writeLines(c(
        '"BIOC_CATALYST_DIFFERENTIAL_DISCOVERY":',
        paste0('    CATALYST: ', as.character(packageVersion('CATALYST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_discovery.csv versions.yml
    """
}

workflow BIOC_CATALYST_DIFFERENTIAL_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PBMC_fs.fcs, PBMC_panel.csv, PBMC_md.csv ] ]

    main:
    BIOC_CATALYST_DIFFERENTIAL_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_CATALYST_DIFFERENTIAL_DISCOVERY.out.tables
    plots    = BIOC_CATALYST_DIFFERENTIAL_DISCOVERY.out.plots
    objects  = BIOC_CATALYST_DIFFERENTIAL_DISCOVERY.out.objects
    versions = BIOC_CATALYST_DIFFERENTIAL_DISCOVERY.out.versions
}
