#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DropletUtils — detect_empty_droplets
// Distinguish cell-containing droplets from empty droplets containing ambient RNA.
// Input: my.counts
// Container: quay.io/biocontainers/bioconductor-dropletutils:1.30.0--r45ha27e39d_0
// Requires: DropletUtils, Matrix
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute barcode ranks and identify knee/inflection points using barcodeRanks. 2. Test each barcode's expression profile against th

nextflow.enable.dsl = 2

process BIOC_DROPLETUTILS_DETECT_EMPTY_DROPLETS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(DropletUtils)
    library(Matrix)
    
    # Read the user input file 'my.counts' from the working directory.
    # We assume 'my.counts' is saved as an RDS file containing the count matrix.
    if (file.exists("my.counts")) {
      my.counts <- readRDS("my.counts")
    } else if (file.exists("my.counts.rds")) {
      my.counts <- readRDS("my.counts.rds")
    } else {
      stop("Error: Input file 'my.counts' (RDS format) not found in the working directory.")
    }
    
    # 1. Compute barcode ranks and identify knee/inflection points using barcodeRanks
    br.out <- barcodeRanks(my.counts)
    
    # Save barcode ranks plot
    pdf("barcode_ranks_plot.pdf")
    plot(br.out\$rank, br.out\$total, log="xy", xlab="Rank", ylab="Total")
    o <- order(br.out\$rank)
    lines(br.out\$rank[o], br.out\$fitted[o], col="red")
    abline(h=metadata(br.out)\$knee, col="dodgerblue", lty=2)
    abline(h=metadata(br.out)\$inflection, col="forestgreen", lty=2)
    legend("bottomleft", lty=2, col=c("dodgerblue", "forestgreen"), 
           legend=c("knee", "inflection"))
    dev.off()
    
    # Save barcode ranks object
    saveRDS(br.out, file="barcode_ranks.rds")
    
    # 2. Test each barcode's expression profile against the ambient profile using emptyDrops
    # Set seed for reproducibility as emptyDrops uses permutation testing
    set.seed(100)
    e.out <- emptyDrops(my.counts)
    
    # Save emptyDrops results table
    write.csv(as.data.frame(e.out), file="empty_drops_results.csv", row.names=TRUE)
    
    # 3. Filter for significant cell-containing droplets based on FDR
    is.cell <- e.out\$FDR <= 0.01
    
    # Save diagnostic plot of total count vs negative log probability
    pdf("empty_drops_plot.pdf")
    plot(e.out\$Total, -e.out\$LogProb, col=ifelse(!is.na(is.cell) & is.cell, "red", "black"),
         xlab="Total UMI count", ylab="-Log Probability")
    dev.off()
    
    # Export the identified cell-containing barcodes
    barcodes <- colnames(my.counts)
    if (is.null(barcodes)) {
      barcodes <- paste0("Barcode_", seq_len(ncol(my.counts)))
    }
    
    results_df <- data.frame(
      Barcode = barcodes,
      Total_UMI = e.out\$Total,
      LogProb = e.out\$LogProb,
      PValue = e.out\$PValue,
      FDR = e.out\$FDR,
      IsCell = !is.na(is.cell) & is.cell
    )
    
    # Write complete results and filtered cell-only results
    write.csv(results_df, file="droplet_classification_summary.csv", row.names=FALSE)
    write.csv(results_df[results_df\$IsCell, ], file="cell_containing_barcodes.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_DROPLETUTILS_DETECT_EMPTY_DROPLETS":',
        paste0('    DropletUtils: ', as.character(packageVersion('DropletUtils')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detect_empty_droplets.csv versions.yml
    """
}

workflow BIOC_DROPLETUTILS_DETECT_EMPTY_DROPLETS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ my.counts ] ]

    main:
    BIOC_DROPLETUTILS_DETECT_EMPTY_DROPLETS(ch_input)

    emit:
    tables   = BIOC_DROPLETUTILS_DETECT_EMPTY_DROPLETS.out.tables
    plots    = BIOC_DROPLETUTILS_DETECT_EMPTY_DROPLETS.out.plots
    objects  = BIOC_DROPLETUTILS_DETECT_EMPTY_DROPLETS.out.objects
    versions = BIOC_DROPLETUTILS_DETECT_EMPTY_DROPLETS.out.versions
}
