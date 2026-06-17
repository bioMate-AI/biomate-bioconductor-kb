#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: monalisa — binned_kmer_enrichment
// Perform an unbiased sequence enrichment analysis using k-mers instead of annotated motifs.
// Input: peaks.bed, methylation_changes.tsv
// Container: quay.io/biocontainers/bioconductor-monalisa:1.16.0--r45hdfd78af_0
// R packages: BSgenome.Mmusculus.UCSC.mm10, Biostrings, ComplexHeatmap, GenomicRanges, JASPAR2020, TFBSTools, circlize, monaLisa, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: heatmap (ComplexHeatmap), heatmap

nextflow.enable.dsl = 2

process BIOC_MONALISA_BINNED_KMER_ENRICHMENT {
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
    .bm_deps <- c("BSgenome.Mmusculus.UCSC.mm10", "Biostrings", "ComplexHeatmap", "GenomicRanges", "JASPAR2020", "TFBSTools", "circlize", "monaLisa", "rtracklayer", "SummarizedExperiment")
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
    library(monaLisa)
    library(SummarizedExperiment)
    library(GenomicRanges)
    library(rtracklayer)
    library(Biostrings)
    library(BSgenome.Mmusculus.UCSC.mm10)
    library(JASPAR2020)
    library(TFBSTools)
    library(ComplexHeatmap)
    library(circlize)
    library(grid)
    
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    
    if (!file.exists("peaks.bed")) {
      stop("Required input file 'peaks.bed' not found in the working directory.")
    }
    if (!file.exists("methylation_changes.tsv")) {
      stop("Required input file 'methylation_changes.tsv' not found in the working directory.")
    }
    
    # Import genomic coordinates
    peaks <- rtracklayer::import("peaks.bed", format = "bed")
    
    # Import numerical values associated with each peak
    meth <- read.delim("methylation_changes.tsv", header = TRUE)
    
    # Align peaks and numerical values if lengths differ
    if (length(peaks) != nrow(meth)) {
      warning("The number of peaks in 'peaks.bed' does not match the number of rows in 'methylation_changes.tsv'. Subsetting to the minimum common length.")
      min_len <- min(length(peaks), nrow(meth))
      peaks <- peaks[1:min_len]
      meth <- meth[1:min_len, , drop = FALSE]
    }
    
    # Identify the numeric column to use for binning
    num_cols <- sapply(meth, is.numeric)
    if (any(num_cols)) {
      meth_val <- meth[[which(num_cols)[1]]]
    } else {
      meth_val <- as.numeric(meth[[1]])
    }
    
    # Filter peaks to keep only those on chromosomes present in the mm10 genome
    peaks\$orig_idx <- seq_along(peaks)
    common_seqs <- intersect(seqlevels(peaks), seqlevels(BSgenome.Mmusculus.UCSC.mm10))
    if (length(common_seqs) == 0) {
      stop("No common chromosomes found between 'peaks.bed' and BSgenome.Mmusculus.UCSC.mm10.")
    }
    peaks <- keepSeqlevels(peaks, common_seqs, pruning.mode = "coarse")
    
    # Resize and trim peaks to avoid length bias
    peaks <- trim(resize(peaks, width = median(width(peaks)), fix = "center"))
    peaks <- peaks[width(peaks) > 0]
    
    # Extract sequences
    lmrseqs <- getSeq(BSgenome.Mmusculus.UCSC.mm10, peaks)
    
    # Align the numerical values to the filtered peaks
    meth_val <- meth_val[peaks\$orig_idx]
    
    # Bin genomic regions based on numerical values
    n_elem <- max(20, floor(length(lmrseqs) / 10))
    bins <- bin(x = meth_val, binmode = "equalN", nElement = n_elem)
    
    # ==========================================
    # --- Generate seSel (Motif Enrichment) ---
    # ==========================================
    # To compare enriched k-mers to motifs, we need a motif enrichment object (seSel).
    # We run a fast motif enrichment using a subset of JASPAR vertebrate motifs.
    pfms <- getMatrixSet(JASPAR2020, opts = list(matrixtype = "PFM", tax_group = "vertebrates"))
    set.seed(123)
    pfms_sub <- pfms[sample(length(pfms), min(50, length(pfms)))]
    pwms <- toPWM(pfms_sub)
    
    se <- calcBinnedMotifEnrR(seqs = lmrseqs, bins = bins, pwmL = pwms)
    
    # Select motifs with significant enrichment (with fallback to top 5 to ensure non-empty)
    sel <- apply(assay(se, "negLog10Padj"), 1, function(x) max(abs(x), 0, na.rm = TRUE)) > 1.0
    if (sum(sel) == 0) {
      max_vals <- apply(assay(se, "negLog10Padj"), 1, function(x) max(abs(x), 0, na.rm = TRUE))
      sel <- rank(-max_vals) <= 5
    }
    seSel <- se[sel, ]
    
    # ==========================================
    # --- Run Binned K-mer Enrichment (Documented Code) ---
    # ==========================================
    
    # Run calcBinnedKmerEnr to find enriched k-mers
    sekm <- calcBinnedKmerEnr(seqs = lmrseqs, bins = bins, kmerLen = 6, includeRevComp = TRUE)
    
    # Filter enriched k-mers (with fallback to top 10 to ensure non-empty)
    selkm <- apply(assay(sekm, "negLog10Padj"), 1, function(x) max(abs(x), 0, na.rm = TRUE)) > 4
    if (sum(selkm) == 0) {
      max_vals_km <- apply(assay(sekm, "negLog10Padj"), 1, function(x) max(abs(x), 0, na.rm = TRUE))
      selkm <- rank(-max_vals_km) <= 10
    }
    sekmSel <- sekm[selkm, ]
    
    # Calculate similarity between enriched k-mers and known motifs using motifKmerSimilarity
    pfmSel <- rowData(seSel)\$motif.pfm
    sims <- motifKmerSimilarity(x = pfmSel, kmers = rownames(sekmSel), includeRevComp = TRUE)
    
    # Plot similarity heatmap with sequence logos
    maxwidth <- max(sapply(TFBSTools::Matrix(pfmSel), ncol))
    seqlogoGrobs <- lapply(pfmSel, seqLogoGrob, xmax = maxwidth)
    hmSeqlogo <- rowAnnotation(logo = annoSeqlogo(seqlogoGrobs, which = "row"), annotation_width = unit(1.5, "inch"), show_annotation_name = FALSE )
    
    # ==========================================
    # --- Save Outputs ---
    # ==========================================
    
    # Save the main SummarizedExperiment object
    saveRDS(sekm, "binned_kmer_enrichment_results.rds")
    
    # Save selected k-mers and their adjusted p-values
    write.csv(as.data.frame(assay(sekmSel, "negLog10Padj")), "selected_kmers_negLog10Padj.csv", row.names = TRUE)
    
    # Save the similarity matrix
    write.csv(as.data.frame(sims), "motif_kmer_similarity_matrix.csv", row.names = TRUE)
    
    # Save the Heatmap plot as a PDF
    pdf("motif_kmer_similarity_heatmap.pdf", width = 10, height = 8)
    draw(Heatmap(sims, 
                 show_row_names = TRUE, 
                 row_names_gp = gpar(fontsize = 8), 
                 show_column_names = TRUE, 
                 column_names_gp = gpar(fontsize = 8), 
                 name = "Similarity", 
                 column_title = "Selected TFs and enriched k-mers", 
                 col = colorRamp2(c(0, 1), c("white", "red")), 
                 right_annotation = hmSeqlogo))
    dev.off()

    writeLines(c(
        '"BIOC_MONALISA_BINNED_KMER_ENRICHMENT":',
        paste0('        monalisa: ', as.character(packageVersion("monalisa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binned_kmer_enrichment.csv versions.yml
    """
}

workflow BIOC_MONALISA_BINNED_KMER_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks.bed, methylation_changes.tsv ] ]

    main:
    BIOC_MONALISA_BINNED_KMER_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MONALISA_BINNED_KMER_ENRICHMENT.out.tables
    plots    = BIOC_MONALISA_BINNED_KMER_ENRICHMENT.out.plots
    objects  = BIOC_MONALISA_BINNED_KMER_ENRICHMENT.out.objects
    versions = BIOC_MONALISA_BINNED_KMER_ENRICHMENT.out.versions
}
