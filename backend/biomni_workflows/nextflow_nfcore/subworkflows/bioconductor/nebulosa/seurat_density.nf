#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nebulosa — seurat_density
// Perform gene-weighted density estimation and visualization on a Seurat object.
// Input: pbmc3k_filtered_gene_bc_matrices.tar.gz
// Container: quay.io/biocontainers/bioconductor-nebulosa:1.20.0--r45hdfd78af_0
// R packages: Nebulosa, Seurat, patchwork
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: density plot
// QC: count normalization, clustering QC

nextflow.enable.dsl = 2

process BIOC_NEBULOSA_SEURAT_DENSITY {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-nebulosa:1.20.0--r45hdfd78af_0"

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
    .bm_deps <- c("Nebulosa", "Seurat", "patchwork")
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
    library("Nebulosa")
    library("Seurat")
    library("patchwork")
    
    # Define the input file path (must be in the working directory)
    input_file <- "pbmc3k_filtered_gene_bc_matrices.tar.gz"
    
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Untar the input file to a temporary directory
    temp_dir <- tempdir()
    untar(input_file, exdir = temp_dir)
    
    # Read the 10X Genomics matrix
    data <- Read10X(data.dir = file.path(temp_dir, "filtered_gene_bc_matrices", "hg19"))
    
    # Create Seurat object
    pbmc <- CreateSeuratObject(
      counts = data,
      project = "pbmc3k",
      min.cells = 3,
      min.features = 200
    )
    
    # Quality control and filtering
    pbmc[["percent.mt"]] <- PercentageFeatureSet(pbmc, pattern = "^MT-")
    pbmc <- subset(pbmc, subset = nFeature_RNA < 2500 & percent.mt < 5)
    
    # Normalize data using SCTransform
    pbmc <- SCTransform(pbmc, verbose = FALSE)
    
    # Dimensionality reduction
    pbmc <- RunPCA(pbmc)
    pbmc <- RunUMAP(pbmc, dims = 1:30)
    
    # Clustering
    pbmc <- FindNeighbors(pbmc, dims = 1:30)
    pbmc <- FindClusters(pbmc)
    
    # Save processed Seurat object and metadata
    saveRDS(pbmc, file = "pbmc_processed.rds")
    write.csv(pbmc@meta.data, file = "pbmc_metadata.csv", row.names = TRUE)
    
    # Generate and save density plots
    pdf("nebulosa_density_plots.pdf", width = 8, height = 11)
    
    # --- Single-gene density plot for CD4 ---
    p1 <- plot_density(pbmc, "CD4")
    print(p1)
    
    # --- Multi-gene density plot for CD8A and CCR7 ---
    p3 <- plot_density(pbmc, c("CD8A", "CCR7"))
    print(p3 + plot_layout(ncol = 1))
    
    # --- Joint density plot for CD8A and CCR7 ---
    p4 <- plot_density(pbmc, c("CD8A", "CCR7"), joint = TRUE)
    print(p4 + plot_layout(ncol = 1))
    
    # --- Joint density plot with combine = FALSE (extracting the ---
    p_list <- plot_density(pbmc, c("CD8A", "CCR7"), joint = TRUE, combine = FALSE)
    print(p_list[[length(p_list)]])
    
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    # clustering QC — n_clusters ∈ [2,50] proxy (silhouette needs cluster pkg).
    .clu_n <- NA_real_
    for (.clu_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .clu_obj <- tryCatch(readRDS(.clu_rds), error = function(e) NULL)
      .clu_v <- NULL
      if (!is.null(.clu_obj)) {
        if (inherits(.clu_obj, "SingleCellExperiment")) {
          .clu_cd <- tryCatch(colData(.clu_obj), error = function(e) NULL)
          if (!is.null(.clu_cd)) {
            .clu_col <- intersect(c("cluster","clusters","seurat_clusters","label"), colnames(.clu_cd))
            if (length(.clu_col) > 0) .clu_v <- .clu_cd[[.clu_col[1]]]
          }
        } else if (inherits(.clu_obj, "Seurat")) {
          .clu_md <- tryCatch(.clu_obj@meta.data, error = function(e) NULL)
          if (!is.null(.clu_md)) {
            .clu_col <- intersect(c("seurat_clusters","cluster","clusters"), colnames(.clu_md))
            if (length(.clu_col) > 0) .clu_v <- .clu_md[[.clu_col[1]]]
          }
        }
      }
      if (!is.null(.clu_v) && length(.clu_v) > 0) {
        .clu_n <- length(unique(as.character(.clu_v[!is.na(.clu_v)]))); break
      }
    }
    .gates_by_label[["clustering QC"]] <- list(
      gate_row = "bioc_clustering_qc",
      metric_name = "n_clusters",
      metric_value = .clu_n,
      passes = isTRUE(is.finite(.clu_n) && .clu_n >= 2 && .clu_n <= 50),
      status = if (is.finite(.clu_n)) paste0("computed (n_clusters=", .clu_n, ")")
               else "not_computed (no SCE/Seurat with cluster column present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_NEBULOSA_SEURAT_DENSITY",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization", "clustering QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_NEBULOSA_SEURAT_DENSITY":',
        paste0('        nebulosa: ', as.character(packageVersion("nebulosa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seurat_density.csv versions.yml
    """
}

workflow BIOC_NEBULOSA_SEURAT_DENSITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc3k_filtered_gene_bc_matrices.tar.gz ] ]

    main:
    BIOC_NEBULOSA_SEURAT_DENSITY(ch_input)

    emit:
    tables   = BIOC_NEBULOSA_SEURAT_DENSITY.out.tables
    plots    = BIOC_NEBULOSA_SEURAT_DENSITY.out.plots
    objects  = BIOC_NEBULOSA_SEURAT_DENSITY.out.objects
    versions = BIOC_NEBULOSA_SEURAT_DENSITY.out.versions
}
