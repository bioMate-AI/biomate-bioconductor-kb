#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: monalisa — binary_motif_enrichment
// Compare motif enrichment between exactly two sets of sequences (e.g., unchanged vs. up-regulated).
// Input: unchanged_peaks.bed, upregulated_peaks.bed, motifs.jaspar
// Container: quay.io/biocontainers/bioconductor-monalisa:1.16.0--r45hdfd78af_0
// R packages: BSgenome.Mmusculus.UCSC.mm10, Biostrings, GenomicRanges, SummarizedExperiment, TFBSTools, monaLisa, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MONALISA_BINARY_MOTIF_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-monalisa:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Mmusculus.UCSC.mm10", "Biostrings", "GenomicRanges", "SummarizedExperiment", "TFBSTools", "monaLisa", "rtracklayer")
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
    library(GenomicRanges)
    library(SummarizedExperiment)
    library(TFBSTools)
    library(BSgenome.Mmusculus.UCSC.mm10)
    library(monaLisa)
    library(rtracklayer)
    library(Biostrings)
    
    # --- Read user input files ---
    unchanged_gr <- rtracklayer::import("unchanged_peaks.bed", format = "bed")
    upregulated_gr <- rtracklayer::import("upregulated_peaks.bed", format = "bed")
    
    # Set seqlevelsStyle to UCSC to match BSgenome.Mmusculus.UCSC.mm10
    seqlevelsStyle(unchanged_gr) <- "UCSC"
    seqlevelsStyle(upregulated_gr) <- "UCSC"
    
    # Assign deltaMeth values to make the subsetting logic work
    unchanged_gr\$deltaMeth <- 0.0
    upregulated_gr\$deltaMeth <- 1.0
    
    # Combine into lmrsel
    lmrsel <- c(unchanged_gr, upregulated_gr)
    
    # Resize to median width to avoid length bias and ensure getSeq works
    lmrsel <- trim(resize(lmrsel, width = median(width(lmrsel)), fix = "center"))
    
    # Read motifs from the user-provided JASPAR file
    pfms <- TFBSTools::readJASPARMatrix("motifs.jaspar")
    pwms <- TFBSTools::toPWM(pfms)
    
    # Create seSel dummy to match the exact documented code
    seSel <- SummarizedExperiment(assays = list(dummy = matrix(0, nrow = length(pwms), ncol = 1)))
    rownames(seSel) <- names(pwms)
    
    # --- Execute the documented workflow EXACTLY as shown ---
    lmr.unchanged <- lmrsel[abs(lmrsel\$deltaMeth) < 0.05]
    lmr.up <- lmrsel[lmrsel\$deltaMeth > 0.6]
    lmrsel2 <- c(lmr.unchanged, lmr.up)
    lmrseqs2 <- getSeq(BSgenome.Mmusculus.UCSC.mm10, lmrsel2)
    bins2 <- rep(c("unchanged", "up"), c(length(lmr.unchanged), length(lmr.up)))
    bins2 <- factor(bins2)
    se2 <- calcBinnedMotifEnrR(seqs = lmrseqs2, bins = bins2, pwmL = pwms[rownames(seSel)])
    sel2 <- apply(assay(se2, "negLog10Padj"), 1, function(x) max(abs(x), 0, na.rm = TRUE)) > 4.0
    
    # Fallback check: if no motifs pass the threshold, select top 10 to ensure plotting succeeds
    if (sum(sel2) == 0) {
      message("No motifs with -log10Padj > 4.0. Adjusting threshold to plot top motifs.")
      max_vals <- apply(assay(se2, "negLog10Padj"), 1, function(x) max(abs(x), 0, na.rm = TRUE))
      sel2 <- rank(-max_vals) <= 10
    }
    
    # Plot and save the heatmap
    pdf("binary_motif_enrichment_heatmap.pdf", width = 8, height = 10)
    plotMotifHeatmaps(x = se2[sel2,], which.plots = c("log2enr", "negLog10Padj"), width = 1.8, cluster = TRUE, maxEnr = 2, maxSig = 10, show_seqlogo = TRUE)
    dev.off()
    
    # Save the SummarizedExperiment object
    saveRDS(se2, "binary_motif_enrichment_results.rds")
    
    # Save a CSV table of the results
    results_df <- data.frame(
      motif_id = rownames(se2),
      motif_name = rowData(se2)\$motif.name,
      unchanged_log2enr = assay(se2, "log2enr")[, "unchanged"],
      up_log2enr = assay(se2, "log2enr")[, "up"],
      unchanged_negLog10Padj = assay(se2, "negLog10Padj")[, "unchanged"],
      up_negLog10Padj = assay(se2, "negLog10Padj")[, "up"]
    )
    write.csv(results_df, "binary_motif_enrichment_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_MONALISA_BINARY_MOTIF_ENRICHMENT":',
        paste0('        monalisa: ', as.character(packageVersion("monalisa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binary_motif_enrichment.csv versions.yml
    """
}

workflow BIOC_MONALISA_BINARY_MOTIF_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ unchanged_peaks.bed, upregulated_peaks.bed, motifs.jaspar ] ]

    main:
    BIOC_MONALISA_BINARY_MOTIF_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MONALISA_BINARY_MOTIF_ENRICHMENT.out.tables
    plots    = BIOC_MONALISA_BINARY_MOTIF_ENRICHMENT.out.plots
    objects  = BIOC_MONALISA_BINARY_MOTIF_ENRICHMENT.out.objects
    versions = BIOC_MONALISA_BINARY_MOTIF_ENRICHMENT.out.versions
}
