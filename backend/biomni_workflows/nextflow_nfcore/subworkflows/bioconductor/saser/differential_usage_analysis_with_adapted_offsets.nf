#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: saser — differential_usage_analysis_with_adapted_offsets
// Perform differential usage/splicing analysis using adapted offsets in DESeq2 or edgeR.
// Input: BAMFiles, gtfFileName
// Container: quay.io/biocontainers/bioconductor-saser:1.6.0--r45hdfd78af_0
// R packages: DESeq2, GenomicAlignments, GenomicFeatures, dplyr, edgeR, saseR, txdbmaker
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SASER_DIFFERENTIAL_USAGE_ANALYSIS_WITH_ADAPTED_OFFSETS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-saser:1.6.0--r45hdfd78af_0"

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
    .bm_deps <- c("DESeq2", "GenomicAlignments", "GenomicFeatures", "dplyr", "edgeR", "saseR", "txdbmaker", "SummarizedExperiment")
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
    library(saseR)
    library(SummarizedExperiment)
    library(edgeR)
    library(DESeq2)
    library(dplyr)
    library(GenomicAlignments)
    library(GenomicFeatures)
    library(txdbmaker)
    
    # -----------------------------------------------------------------------------
    # --- Read User Input Files from Working Directory ---
    # -----------------------------------------------------------------------------
    
    # Locate GTF file in the working directory
    gtf_files <- list.files(pattern = "\\\\.gtf\$", full.names = TRUE)
    if (length(gtf_files) == 0) {
      stop("Error: No GTF file (.gtf) found in the working directory.")
    }
    gtfFileName <- gtf_files[1]
    message("Using GTF file: ", gtfFileName)
    
    # Locate BAM files in the working directory
    BAMFiles <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    if (length(BAMFiles) == 0) {
      stop("Error: No BAM files (.bam) found in the working directory.")
    }
    message("Found ", length(BAMFiles), " BAM files.")
    
    # -----------------------------------------------------------------------------
    # --- Convert GTF to TxDb and Extract Exonic Parts ---
    # -----------------------------------------------------------------------------
    message("Creating TxDb from GTF...")
    genomeTxDb <- txdbmaker::makeTxDbFromGFF(gtfFileName)
    
    message("Extracting exonic parts...")
    flattenedAnnotation <- GenomicFeatures::exonicParts(genomeTxDb, 
                                                        linked.to.single.gene.only = TRUE)
    
    # -----------------------------------------------------------------------------
    # --- Count Overlaps Using summarizeOverlaps ---
    # -----------------------------------------------------------------------------
    message("Counting overlaps...")
    se <- GenomicAlignments::summarizeOverlaps(
      flattenedAnnotation,
      BAMFiles, 
      singleEnd = TRUE, 
      ignore.strand = TRUE
    )
    
    # -----------------------------------------------------------------------------
    # --- Define Experimental Conditions in colData ---
    # -----------------------------------------------------------------------------
    # Dynamically assign conditions based on the number of BAM files available.
    # We split the samples as evenly as possible into "control" and "case".
    n_samples <- length(BAMFiles)
    half_samples <- ceiling(n_samples / 2)
    conditions <- factor(rep(c("control", "case"), each = half_samples, length.out = n_samples))
    colData(se)\$condition <- conditions
    message("Assigned conditions: ", paste(conditions, collapse = ", "))
    
    # -----------------------------------------------------------------------------
    # --- Aggregate Counts Per Gene to Calculate Gene-Level Offsets ---
    # -----------------------------------------------------------------------------
    message("Calculating gene-level offsets...")
    counts <- assays(se)\$counts
    offsetsGene <- aggregate(counts,
                             by = list("gene" = rowData(se)\$gene_id), FUN = sum) 
    offsets <- offsetsGene[match(rowData(se)\$gene_id, offsetsGene\$gene), ] %>% 
                         mutate("gene" = NULL) %>% 
                         as.matrix() 
    
    # -----------------------------------------------------------------------------
    # --- Adjust Zero Offsets and Counts to 1 ---
    # -----------------------------------------------------------------------------
    index <- offsets == 0
    counts[index] <- 1
    offsets[index] <- 1
    
    # -----------------------------------------------------------------------------
    # --- Run DESeq2 with Custom Offsets ---
    # -----------------------------------------------------------------------------
    message("Running DESeq2 analysis...")
    dds <- DESeqDataSetFromMatrix(countData = counts,
                                  colData = colData(se),
                                  rowData = rowData(se),
                                  design = ~ condition)
    normalizationFactors(dds) <- offsets
    dds <- DESeq2::estimateDispersionsGeneEst(dds)
    dispersions(dds) <- mcols(dds)\$dispGeneEst
    dds <- DESeq2::nbinomWaldTest(dds)
    results_dds <- DESeq2::results(dds)
    
    # -----------------------------------------------------------------------------
    # --- Run edgeR with Custom Offsets ---
    # -----------------------------------------------------------------------------
    message("Running edgeR analysis...")
    DGE <- DGEList(counts = counts)
    DGE\$offset <- log(offsets)
    design <- model.matrix(~condition, data = colData(se))
    DGE <- edgeR::estimateDisp(DGE, design = design)
    fitDGE <- edgeR::glmFit(DGE, design = design)
    results_DGE <- edgeR::glmLRT(fitDGE, coef = 2)
    
    # -----------------------------------------------------------------------------
    # --- Save Outputs ---
    # -----------------------------------------------------------------------------
    message("Saving results...")
    
    # Save tabular results
    write.csv(as.data.frame(results_dds), "deseq2_differential_usage_results.csv", row.names = TRUE)
    write.csv(as.data.frame(edgeR::topTags(results_DGE, n = Inf)), "edger_differential_usage_results.csv", row.names = TRUE)
    
    # Save R objects
    saveRDS(dds, "deseq2_dds_object.rds")
    saveRDS(DGE, "edger_dge_object.rds")
    
    # Generate diagnostic plots
    pdf("differential_usage_diagnostic_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    # DESeq2 MA Plot
    if (!is.null(results_dds)) {
      plot(results_dds\$baseMean, results_dds\$log2FoldChange, log = "x", 
           pch = 20, cex = 0.5, col = ifelse(results_dds\$padj < 0.05, "red", "black"),
           xlab = "Mean of Normalized Counts", ylab = "Log2 Fold Change",
           main = "DESeq2 MA Plot")
      abline(h = 0, col = "blue", lwd = 2)
    }
    # edgeR MD Plot
    edgeR::plotMD(results_DGE, main = "edgeR MD Plot")
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_SASER_DIFFERENTIAL_USAGE_ANALYSIS_WITH_ADAPTED_OFFSETS":',
        paste0('        saser: ', as.character(packageVersion("saser")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_usage_analysis_with_adapted_offsets.csv versions.yml
    """
}

workflow BIOC_SASER_DIFFERENTIAL_USAGE_ANALYSIS_WITH_ADAPTED_OFFSETS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BAMFiles, gtfFileName ] ]

    main:
    BIOC_SASER_DIFFERENTIAL_USAGE_ANALYSIS_WITH_ADAPTED_OFFSETS(ch_input)

    emit:
    tables   = BIOC_SASER_DIFFERENTIAL_USAGE_ANALYSIS_WITH_ADAPTED_OFFSETS.out.tables
    plots    = BIOC_SASER_DIFFERENTIAL_USAGE_ANALYSIS_WITH_ADAPTED_OFFSETS.out.plots
    objects  = BIOC_SASER_DIFFERENTIAL_USAGE_ANALYSIS_WITH_ADAPTED_OFFSETS.out.objects
    versions = BIOC_SASER_DIFFERENTIAL_USAGE_ANALYSIS_WITH_ADAPTED_OFFSETS.out.versions
}
