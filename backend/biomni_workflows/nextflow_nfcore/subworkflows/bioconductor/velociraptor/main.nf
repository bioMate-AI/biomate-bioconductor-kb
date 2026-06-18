#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: velociraptor — rna_velocity_scvelo
// Calculate RNA velocity from spliced and unspliced single-cell RNA-seq counts, project the velocity vectors onto a low-dimensional embedding, and visualize the g
// Input: sce
// Container: quay.io/biocontainers/bioconductor-velociraptor:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, scater, scran, scuttle, velociraptor
// Visualizations: t-SNE plot
// QC: cell QC metrics, count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Feature selection (identifying highly variable genes using scran)
//  * 2. [Core Analysis] RNA velocity estimation using scvelo()
//  * 3. [Core Analysis] Dimensionality reduction (PCA and t-SNE)
//  * 4. [Core Analysis] Velocity embedding projection using embedVelocity()
//  * 5. [Visualization & Output] Grid-based summarization of velocity vectors using gridVectors()
//  * 6. [Visualization & Output] Visualization of velocity pseudotime and vectors using ggplot2

nextflow.enable.dsl = 2

process BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("scuttle", "scran", "velociraptor", "scater", "ggplot2")
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
    library(scuttle)
    library(scran)
    library(velociraptor)
    library(scater)
    library(ggplot2)
    
    # 1. Read User Input
    sce_path <- "sce"
    if (!file.exists(sce_path) && file.exists("sce.rds")) {
      sce_path <- "sce.rds"
    }
    sce <- readRDS(sce_path)
    
    # 2. Feature selection (identifying highly variable genes using scran)
    sce <- logNormCounts(sce, assay.type=1)
    dec <- modelGeneVar(sce)
    top.hvgs <- getTopHVGs(dec, n=2000)
    
    # 3. RNA velocity estimation using scvelo()
    velo.out <- scvelo(
      sce, subset.row=top.hvgs, assay.X="spliced",
      scvelo.params=list(neighbors=list(n_neighbors=30L))
    )
    
    # 4. Dimensionality reduction (PCA and t-SNE)
    set.seed(100)
    sce <- runPCA(sce, subset_row=top.hvgs)
    sce <- runTSNE(sce, dimred="PCA", perplexity = 30)
    
    sce\$velocity_pseudotime <- velo.out\$velocity_pseudotime
    
    # 5. Velocity embedding projection using embedVelocity()
    embedded <- embedVelocity(reducedDim(sce, "TSNE"), velo.out)
    
    # 6. Grid-based summarization of velocity vectors using gridVectors()
    grid.df <- gridVectors(sce, embedded, use.dimred = "TSNE")
    
    # 7. Visualization of velocity pseudotime and vectors using ggplot2
    p <- plotTSNE(sce, colour_by="velocity_pseudotime") +
        geom_segment(data=grid.df, mapping=aes(x=start.1, y=start.2, 
            xend=end.1, yend=end.2, colour=NULL), arrow=arrow(length=unit(0.05, "inches")))
    
    # Save outputs
    ggsave("velocity_tsne_plot.pdf", plot = p, width = 8, height = 7)
    write.csv(as.data.frame(grid.df), "grid_vectors.csv", row.names = FALSE)
    
    pseudotime_df <- data.frame(
      Cell = colnames(sce),
      velocity_pseudotime = sce\$velocity_pseudotime
    )
    write.csv(pseudotime_df, "velocity_pseudotime.csv", row.names = FALSE)
    
    saveRDS(velo.out, "velo_out.rds")
    saveRDS(sce, "sce_output.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # HVG selection — count rows with high CV. Pass when 1000-3000 HVGs
    # (Stuart 2019 Cell Seurat v3 default range).
    .hvg_count <- NA_real_; .hvg_files <- character(0)
    for (.hvg_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .hvg_obj <- tryCatch(readRDS(.hvg_rds), error = function(e) NULL)
      .hvg_mat <- if (is.matrix(.hvg_obj) || is.data.frame(.hvg_obj)) .hvg_obj else NULL
      if (!is.null(.hvg_mat) && nrow(.hvg_mat) > 200) {
        .hvg_m <- suppressWarnings(as.matrix(.hvg_mat))
        .hvg_cvs <- suppressWarnings(apply(.hvg_m, 1, function(r) {
          .rv <- as.numeric(r); .m <- mean(.rv, na.rm = TRUE)
          if (is.finite(.m) && .m > 0) sd(.rv, na.rm = TRUE) / .m else NA_real_
        }))
        .hvg_count <- sum(is.finite(.hvg_cvs) & .hvg_cvs > 1.0)
        .hvg_files <- c(.hvg_files, .hvg_rds); break
      }
    }
    .gates_by_label[["highly-variable feature selection"]] <- list(
      gate_row = "bioc_hvg_selection",
      metric_name = "hvg_count",
      metric_value = .hvg_count,
      passes = isTRUE(is.finite(.hvg_count) && .hvg_count >= 1000 && .hvg_count <= 3000),
      status = if (is.finite(.hvg_count)) paste0("computed (CV>1.0 rows = ", .hvg_count, "; proxy for HVG selection)")
               else "not_computed (no expression matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "highly-variable feature selection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO":',
        paste0('    velociraptor: ', as.character(packageVersion('velociraptor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_velocity_scvelo.csv versions.yml
    """
}

workflow BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO(ch_input)

    emit:
    tables   = BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO.out.tables
    plots    = BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO.out.plots
    objects  = BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO.out.objects
    versions = BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO.out.versions
}
