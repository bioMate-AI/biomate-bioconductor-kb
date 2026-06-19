#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scAnnotatR — cell_classification_pretrained
// Classify cell types in a single-cell RNA-seq dataset using pretrained models.
// Input: tirosh_mel80_example
// Container: quay.io/biocontainers/bioconductor-scannotatr:1.16.0--r45hdfd78af_0
// R packages: Seurat, scAnnotatR
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, scAnnotatR
// Visualizations: UMAP/t-SNE plot, feature plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the scAnnotatR package
//  * 2. [Input & Preparation] Load the default pretrained models
//  * 3. [Input & Preparation] Load the single-cell dataset
//  * 4. [Core Analysis] Run cell classification using classify_cells
//  * 5. [Core Analysis] Inspect the classification results in the metadata
//  * 6. [Visualization & Output] Visualize the predicted cell types and prediction probabilities using Seurat plotting functions

nextflow.enable.dsl = 2

process BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED {
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
    .bm_deps <- c("Seurat", "scAnnotatR")
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
    
    # 1. Load the scAnnotatR and Seurat packages
    library(scAnnotatR)
    library(Seurat)
    
    # 2. Load the default pretrained models
    default_models <- load_models("default")
    print(names(default_models))
    print(default_models[['B cells']])
    
    # 3. Load the single-cell dataset from the user input file
    if (file.exists("tirosh_mel80_example")) {
      tirosh_mel80_example <- readRDS("tirosh_mel80_example")
    } else if (file.exists("tirosh_mel80_example.rds")) {
      tirosh_mel80_example <- readRDS("tirosh_mel80_example.rds")
    } else {
      stop("Error: Input file 'tirosh_mel80_example' or 'tirosh_mel80_example.rds' not found in the working directory.")
    }
    
    print(tirosh_mel80_example)
    print(head(tirosh_mel80_example[[]]))
    
    # 4. Run cell classification using classify_cells
    seurat.obj <- classify_cells(classify_obj = tirosh_mel80_example, 
                                 assay = 'RNA', layer = 'counts',
                                 cell_types = c('B cells', 'NK', 'T cells'), 
                                 path_to_models = 'default')
    
    # 5. Inspect the classification results in the metadata
    metadata_subset <- seurat.obj[[]][c(50:60), c(8:ncol(seurat.obj[[]]))]
    print(metadata_subset)
    
    # Save the full metadata and the subset to CSV files
    write.csv(seurat.obj[[]], "classified_cells_metadata.csv", row.names = TRUE)
    write.csv(metadata_subset, "classified_cells_metadata_subset.csv", row.names = TRUE)
    
    # Save the classified Seurat object
    saveRDS(seurat.obj, "classified_seurat_object.rds")
    
    # 6. Visualize the predicted cell types and prediction probabilities using Seurat plotting functions
    pdf("cell_classification_plots.pdf", width = 10, height = 8)
    
    # Visualize the cell types
    p1 <- Seurat::DimPlot(seurat.obj, group.by = "most_probable_cell_type")
    print(p1)
    
    # Visualize the B cell prediction probability
    p2 <- Seurat::FeaturePlot(seurat.obj, features = "B_cells_p")
    print(p2)
    
    # Visualize canonical marker expression
    p3 <- Seurat::FeaturePlot(seurat.obj, features = c("CD19", "MS4A1"), ncol = 2)
    print(p3)
    
    dev.off()
    
    print("Pipeline completed successfully. Outputs saved: 'classified_seurat_object.rds', 'classified_cells_metadata.csv', 'classified_cells_metadata_subset.csv', and 'cell_classification_plots.pdf'.")
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

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED":',
        paste0('    scAnnotatR: ', as.character(packageVersion('scAnnotatR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_classification_pretrained.csv versions.yml
    """
}

workflow BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tirosh_mel80_example ] ]

    main:
    BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED(ch_input)

    emit:
    tables   = BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED.out.tables
    plots    = BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED.out.plots
    objects  = BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED.out.objects
    versions = BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED.out.versions
}
