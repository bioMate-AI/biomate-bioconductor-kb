#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geomeTriD — chromatin_2d_loop_bouquet
// Plot chromatin interactions in 2D as a loop bouquet with nodes (regions) and edges (interactions).
// Input: gi.rds, TxDb.Hsapiens.UCSC.hg19.knownGene
// Container: quay.io/biocontainers/bioconductor-geometrid:1.4.1--r45h575d39b_0
// Requires: GenomicFeatures, GenomicRanges, InteractionSet, TxDb.Hsapiens.UCSC.hg19.knownGene, geomeTriD, org.Hs.eg.db
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load interaction data and define range
//  * 2. [Input & Preparation] Prepare gene and cRE annotations
//  * 3. [Visualization & Output] Plot the 2D loop bouquet using loopBouquetPlot

nextflow.enable.dsl = 2

process BIOC_GEOMETRID_CHROMATIN_2D_LOOP_BOUQUET {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    library(geomeTriD)
    library(GenomicRanges)
    library(org.Hs.eg.db)
    library(InteractionSet)
    library(GenomicFeatures)
    
    # 1. Load interaction data and define range
    if (!file.exists("gi.rds")) {
      stop("Required input file 'gi.rds' not found in the working directory.")
    }
    gi_chr2 <- readRDS("gi.rds")
    
    # Define range to plot dynamically based on the input data
    range_chr2 <- range(regions(gi_chr2))
    
    # 2. Prepare gene and cRE annotations
    # Load TxDb from the user-provided file or fallback to the package
    if (file.exists("TxDb.Hsapiens.UCSC.hg19.knownGene")) {
      txdb <- tryCatch({
        GenomicFeatures::loadDb("TxDb.Hsapiens.UCSC.hg19.knownGene")
      }, error = function(e) {
        tryCatch({
          readRDS("TxDb.Hsapiens.UCSC.hg19.knownGene")
        }, error = function(e2) {
          library(TxDb.Hsapiens.UCSC.hg19.knownGene)
          TxDb.Hsapiens.UCSC.hg19.knownGene
        })
      })
    } else {
      if (!requireNamespace("TxDb.Hsapiens.UCSC.hg19.knownGene", quietly = TRUE)) {
        stop("TxDb.Hsapiens.UCSC.hg19.knownGene package or file is required but not found.")
      }
      library(TxDb.Hsapiens.UCSC.hg19.knownGene)
      txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    }
    
    gene_hg19 <- suppressMessages(genes(txdb))
    feature.gr_chr2 <- subsetByOverlaps(gene_hg19, range_chr2)
    
    # Set seed for reproducibility of sample() calls
    set.seed(123)
    
    feature.gr_chr2\$col <- sample(2:7, length(feature.gr_chr2), replace = TRUE)
    feature.gr_chr2\$type <- sample(c("cRE", "gene"),
      length(feature.gr_chr2),
      replace = TRUE,
      prob = c(0.1, 0.9)
    )
    feature.gr_chr2\$pch <- rep(NA, length(feature.gr_chr2))
    feature.gr_chr2\$pch[feature.gr_chr2\$type == "cRE"] <- 11
    
    symbol <- mget(feature.gr_chr2\$gene_id, org.Hs.egSYMBOL, ifnotfound = NA)
    symbol <- unlist(lapply(symbol, function(.ele) .ele[1]))
    feature.gr_chr2\$label <- symbol
    
    # Save the prepared annotations
    saveRDS(feature.gr_chr2, "feature_gr_chr2.rds")
    write.csv(as.data.frame(feature.gr_chr2), "feature_gr_chr2.csv", row.names = FALSE)
    
    # 3. Plot the 2D loop bouquet using loopBouquetPlot
    pdf("loop_bouquet_plot.pdf", width = 10, height = 8)
    geomeTriD::loopBouquetPlot(gi_chr2, range_chr2, feature.gr_chr2)
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved: 'feature_gr_chr2.rds', 'feature_gr_chr2.csv', 'loop_bouquet_plot.pdf'.")

    writeLines(c(
        '"BIOC_GEOMETRID_CHROMATIN_2D_LOOP_BOUQUET":',
        paste0('    geomeTriD: ', as.character(packageVersion('geomeTriD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromatin_2d_loop_bouquet.csv versions.yml
    """
}

workflow BIOC_GEOMETRID_CHROMATIN_2D_LOOP_BOUQUET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gi.rds, TxDb.Hsapiens.UCSC.hg19.knownGene ] ]

    main:
    BIOC_GEOMETRID_CHROMATIN_2D_LOOP_BOUQUET(ch_input)

    emit:
    tables   = BIOC_GEOMETRID_CHROMATIN_2D_LOOP_BOUQUET.out.tables
    plots    = BIOC_GEOMETRID_CHROMATIN_2D_LOOP_BOUQUET.out.plots
    objects  = BIOC_GEOMETRID_CHROMATIN_2D_LOOP_BOUQUET.out.objects
    versions = BIOC_GEOMETRID_CHROMATIN_2D_LOOP_BOUQUET.out.versions
}
