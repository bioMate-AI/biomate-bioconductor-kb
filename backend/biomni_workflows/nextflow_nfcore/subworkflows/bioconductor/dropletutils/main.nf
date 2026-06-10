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
    library(DropletUtils)
    library(SingleCellExperiment)
    library(Matrix)
    
    # ==========================================
    # 1. Load the 10X count matrix
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
    # 2. Compute barcode rank statistics
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
    # 3. Detect cell-containing droplets
    # ==========================================
    
    set.seed(100)
    e.out <- emptyDrops(my.counts)
    
    # Save emptyDrops results to CSV
    write.csv(as.data.frame(e.out), "empty_drops_results.csv", row.names=TRUE)
    
    # ==========================================
    # 4. Filter results based on FDR
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

    cat <<-END_VERSIONS > versions.yml
    "BIOC_DROPLETUTILS_IMPORT_AND_FILTER_10X_DATA":
        dropletutils: \$(Rscript -e 'cat(as.character(packageVersion("dropletutils")))')
    END_VERSIONS
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
