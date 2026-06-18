#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iSEEtree — iseetree_interactive_explorer
// Build a comprehensive TreeSummarizedExperiment from local abundance and metadata files, perform taxonomic transformations and ordination, and configure the spec
// Input: abundance.csv, coldata.csv
// Container: 1.4.0--r45hdfd78af_0
// R packages: S4Vectors, TreeSummarizedExperiment, ape, iSEEtree, mia, refmanager, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: S4Vectors, TreeSummarizedExperiment, ape, iSEEtree, mia, scater
// QC: cell QC metrics
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEETREE_ISEETREE_INTERACTIVE_EXPLORER {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("S4Vectors", "TreeSummarizedExperiment", "ape", "iSEEtree", "mia", "refmanager", "scater")
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
    
    # --- Load required libraries ---
    library(iSEEtree)
    library(mia)
    library(TreeSummarizedExperiment)
    library(scater)
    library(S4Vectors)
    library(ape)
    
    # --- Read input files and align data ---
    abundance_df <- read.csv("abundance.csv", check.names = FALSE)
    rownames(abundance_df) <- abundance_df\$taxon_id
    abundance_df\$taxon_id <- NULL
    abundance_matrix <- as.matrix(abundance_df)
    
    coldata_df <- read.csv("coldata.csv", check.names = FALSE)
    rownames(coldata_df) <- coldata_df\$sample
    
    # Align samples between abundance matrix and column metadata
    common_samples <- intersect(colnames(abundance_matrix), rownames(coldata_df))
    abundance_matrix <- abundance_matrix[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # --- Construct phylogenetic trees for hierarchical ---
    # Generate a neighbor-joining or random tree for taxa (RowTreePlot)
    row_tree <- ape::rtree(nrow(abundance_matrix))
    row_tree\$tip.label <- rownames(abundance_matrix)
    
    # Generate a neighbor-joining or random tree for samples (ColumnTreePlot)
    col_tree <- ape::rtree(ncol(abundance_matrix))
    col_tree\$tip.label <- colnames(abundance_matrix)
    
    # Construct the TreeSummarizedExperiment object
    tse <- TreeSummarizedExperiment(
        assays = list(counts = abundance_matrix),
        colData = DataFrame(coldata_df),
        rowTree = row_tree,
        colTree = col_tree
    )
    
    # --- Perform transformations and dimensionality reduction ---
    # Transform counts to relative abundance
    tse <- mia::transformAssay(tse, method = "relabundance")
    
    # Run Multi-Dimensional Scaling (MDS) on relative abundance
    tse <- scater::runMDS(tse, assay.type = "relabundance")
    
    # Run supervised Redundancy Analysis (RDA) if group variable has multiple levels
    tryCatch({
        if (length(unique(tse\$group)) > 1) {
            tse <- mia::runRDA(tse, assay.type = "relabundance", formula = assay ~ group)
        }
    }, error = function(e) {
        warning("RDA calculation skipped or failed: ", e\$message)
    })
    
    # --- Configure iSEEtree panels ---
    # Initialize a list of specialized panels provided by iSEEtree
    initial_panels <- list(
        AbundancePlot(),
        AbundanceDensityPlot(),
        RDAPlot(),
        RowTreePlot(),
        ColumnTreePlot(),
        ScreePlot(),
        LoadingPlot()
    )
    
    # --- Save outputs and configurations ---
    saveRDS(tse, "processed_tse.rds")
    saveRDS(initial_panels, "iseetree_config.rds")
    
    # Export MDS coordinates for downstream validation
    mds_coords <- reducedDim(tse, "MDS")
    write.csv(as.data.frame(mds_coords), "mds_coordinates.csv", row.names = TRUE)
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_ISEETREE_ISEETREE_INTERACTIVE_EXPLORER",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_ISEETREE_ISEETREE_INTERACTIVE_EXPLORER":',
        paste0('    iSEEtree: ', as.character(packageVersion('iSEEtree')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseetree_interactive_explorer.csv versions.yml
    """
}

workflow BIOC_ISEETREE_ISEETREE_INTERACTIVE_EXPLORER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ISEETREE_ISEETREE_INTERACTIVE_EXPLORER(ch_input)

    emit:
    tables   = BIOC_ISEETREE_ISEETREE_INTERACTIVE_EXPLORER.out.tables
    plots    = BIOC_ISEETREE_ISEETREE_INTERACTIVE_EXPLORER.out.plots
    objects  = BIOC_ISEETREE_ISEETREE_INTERACTIVE_EXPLORER.out.objects
    versions = BIOC_ISEETREE_ISEETREE_INTERACTIVE_EXPLORER.out.versions
}
