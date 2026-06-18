#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dropletutils — import_and_filter_10x_data
// Load 10X Genomics UMI count matrices, compute barcode ranks, and distinguish cell-containing droplets from empty droplets.
// Input: dir.name, my.counts
// Container: quay.io/biocontainers/bioconductor-dropletutils:1.30.0--r45ha27e39d_0
// R packages: Matrix, SingleCellExperiment, DropletUtils, knitr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: cell QC metrics

nextflow.enable.dsl = 2

process BIOC_DROPLETUTILS_IMPORT_AND_FILTER_10X_DATA {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-dropletutils:1.30.0--r45ha27e39d_0"

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
    .bm_deps <- c("Matrix", "SingleCellExperiment", "DropletUtils", "knitr")
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
    library(DropletUtils)
    library(SingleCellExperiment)
    library(Matrix)
    
    # ==========================================
    # --- Load the 10X count matrix ---
    # ==========================================
    
    # Define input directory name
    dir.name <- "dir.name"
    
    # Fallback to current directory if dir.name does not exist but 10X files are present
    if (!dir.exists(dir.name)) {
      if (file.exists("matrix.mtx") || file.exists("matrix.mtx.gz")) {
        dir.name <- "."
      } else {
        stop("Error: Directory 'dir.name' or 10X files (matrix.mtx, barcodes.tsv, genes.tsv) not found in the working directory.")
      }
    }
    
    # Load 10X Genomics data into a SingleCellExperiment object
    sce <- read10xCounts(dir.name)
    
    # Define the UMI count matrix (my.counts)
    # Read from 'my.counts.rds' or 'my.counts.mtx' if explicitly provided,
    # otherwise extract directly from the loaded SingleCellExperiment object.
    if (file.exists("my.counts.rds")) {
      my.counts <- readRDS("my.counts.rds")
    } else if (file.exists("my.counts.mtx")) {
      my.counts <- readMM("my.counts.mtx")
    } else {
      my.counts <- counts(sce)
    }
    
    # ==========================================
    # --- Compute barcode rank statistics ---
    # ==========================================
    
    br.out <- barcodeRanks(my.counts)
    
    # Save barcode ranks plot to PDF
    pdf("barcode_ranks_plot.pdf", width=7, height=7)
    plot(br.out\$rank, br.out\$total, log="xy", xlab="Rank", ylab="Total")
    o <- order(br.out\$rank)
    lines(br.out\$rank[o], br.out\$fitted[o], col="red")
    abline(h=metadata(br.out)\$knee, col="dodgerblue", lty=2)
    abline(h=metadata(br.out)\$inflection, col="forestgreen", lty=2)
    legend("bottomleft", lty=2, col=c("dodgerblue", "forestgreen"), legend=c("knee", "inflection"))
    dev.off()
    
    # Save barcode ranks statistics to CSV
    write.csv(as.data.frame(br.out), "barcode_ranks_stats.csv", row.names=TRUE)
    
    # ==========================================
    # --- Detect cell-containing droplets ---
    # ==========================================
    
    set.seed(100)
    e.out <- emptyDrops(my.counts)
    
    # Save emptyDrops results to CSV
    write.csv(as.data.frame(e.out), "empty_drops_results.csv", row.names=TRUE)
    
    # ==========================================
    # --- Filter results based on FDR ---
    # ==========================================
    
    is.cell <- e.out\$FDR <= 0.01
    cell_count <- sum(is.cell, na.rm=TRUE)
    
    # Print summary tables to console
    cat("Number of detected cell-containing droplets (FDR <= 0.01):", cell_count, "\n")
    print(table(Limited=e.out\$Limited, Significant=is.cell))
    
    # Save empty drops diagnostic plot to PDF
    pdf("empty_drops_plot.pdf", width=7, height=7)
    plot(e.out\$Total, -e.out\$LogProb, col=ifelse(is.cell, "red", "black"), xlab="Total UMI count", ylab="-Log Probability")
    dev.off()
    
    # Filter the SingleCellExperiment object and save to RDS
    # Ensure NA values in is.cell are treated as FALSE to avoid subscript errors
    keep.cells <- is.cell & !is.na(is.cell)
    sce_filtered <- sce[, keep.cells]
    saveRDS(sce_filtered, "filtered_cells_sce.rds")
    
    cat("Pipeline completed successfully. Outputs saved: barcode_ranks_plot.pdf, barcode_ranks_stats.csv, empty_drops_results.csv, empty_drops_plot.pdf, filtered_cells_sce.rds\n")
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
      process = "BIOC_DROPLETUTILS_IMPORT_AND_FILTER_10X_DATA",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DROPLETUTILS_IMPORT_AND_FILTER_10X_DATA":',
        paste0('        dropletutils: ', as.character(packageVersion("dropletutils")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_import_and_filter_10x_data.csv versions.yml
    """
}

workflow BIOC_DROPLETUTILS_IMPORT_AND_FILTER_10X_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dir.name, my.counts ] ]

    main:
    BIOC_DROPLETUTILS_IMPORT_AND_FILTER_10X_DATA(ch_input)

    emit:
    tables   = BIOC_DROPLETUTILS_IMPORT_AND_FILTER_10X_DATA.out.tables
    plots    = BIOC_DROPLETUTILS_IMPORT_AND_FILTER_10X_DATA.out.plots
    objects  = BIOC_DROPLETUTILS_IMPORT_AND_FILTER_10X_DATA.out.objects
    versions = BIOC_DROPLETUTILS_IMPORT_AND_FILTER_10X_DATA.out.versions
}
