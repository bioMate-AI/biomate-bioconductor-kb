#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dropletutils — demultiplex_hashed_libraries
// Demultiplex cell-hashing libraries to assign cell-containing barcodes to their sample of origin and identify doublets.
// Input: y
// Container: quay.io/biocontainers/bioconductor-dropletutils:1.30.0--r45ha27e39d_0
// R packages: DropletUtils
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DROPLETUTILS_DEMULTIPLEX_HASHED_LIBRARIES {
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
    .bm_deps <- c("DropletUtils")
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
    
    # Set seed for reproducibility (emptyDrops uses permutation testing)
    set.seed(10000)
    
    # Read input file 'y' (matrix of HTO counts) from the working directory
    if (file.exists("y.rds")) {
      y <- readRDS("y.rds")
    } else if (file.exists("y.csv")) {
      y <- as.matrix(read.csv("y.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("y.tsv")) {
      y <- as.matrix(read.delim("y.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Required input file 'y' (matrix of HTO counts as RDS, CSV, or TSV) not found in the working directory.")
    }
    
    # Ensure y is a matrix
    y <- as.matrix(y)
    
    # --- Identify cell-containing barcodes using emptyDrops with ---
    hto.calls <- emptyDrops(y, lower=500)
    has.cell <- hto.calls\$FDR <= 0.001
    
    # Print summary of cell-containing barcodes
    cat("Summary of cell-containing barcodes (FDR <= 0.001):\n")
    print(summary(has.cell))
    
    # Save emptyDrops results
    saveRDS(hto.calls, "hto_calls.rds")
    write.csv(as.data.frame(hto.calls), "hto_calls.csv", row.names = TRUE)
    
    # --- Demultiplex the cell-containing barcodes using hashedDrops ---
    demux <- hashedDrops(y[,which(has.cell)], ambient=metadata(hto.calls)\$ambient)
    
    # Save demultiplexing results
    saveRDS(demux, "demux_results.rds")
    write.csv(as.data.frame(demux), "demux_results.csv", row.names = TRUE)
    
    # --- Identify confident singlets and doublets ---
    # Print table of confident calls
    conf_table <- table(demux\$Best[demux\$Confident])
    cat("\nTable of confident calls by sample of origin:\n")
    print(conf_table)
    
    # Save the table to a text file
    write.table(as.data.frame(conf_table), "confident_singlets_summary.txt", sep="\t", quote=FALSE, row.names=FALSE)
    
    # Generate and save the diagnostic plot
    colors <- ifelse(demux\$Confident, "black", ifelse(demux\$Doublet, "red", "grey"))
    
    pdf("demux_plot.pdf", width=7, height=7)
    plot(demux\$LogFC, demux\$LogFC2, col=colors, 
         xlab="Log-fold change between best and second HTO", 
         ylab="Log-fold change between second HTO and ambient")
    dev.off()
    
    cat("\nPipeline completed successfully. Outputs written to 'hto_calls.rds', 'hto_calls.csv', 'demux_results.rds', 'demux_results.csv', 'confident_singlets_summary.txt', and 'demux_plot.pdf'.\n")

    writeLines(c(
        '"BIOC_DROPLETUTILS_DEMULTIPLEX_HASHED_LIBRARIES":',
        paste0('        dropletutils: ', as.character(packageVersion("dropletutils")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_demultiplex_hashed_libraries.csv versions.yml
    """
}

workflow BIOC_DROPLETUTILS_DEMULTIPLEX_HASHED_LIBRARIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ y ] ]

    main:
    BIOC_DROPLETUTILS_DEMULTIPLEX_HASHED_LIBRARIES(ch_input)

    emit:
    tables   = BIOC_DROPLETUTILS_DEMULTIPLEX_HASHED_LIBRARIES.out.tables
    plots    = BIOC_DROPLETUTILS_DEMULTIPLEX_HASHED_LIBRARIES.out.plots
    objects  = BIOC_DROPLETUTILS_DEMULTIPLEX_HASHED_LIBRARIES.out.objects
    versions = BIOC_DROPLETUTILS_DEMULTIPLEX_HASHED_LIBRARIES.out.versions
}
