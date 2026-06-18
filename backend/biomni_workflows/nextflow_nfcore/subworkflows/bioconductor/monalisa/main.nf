#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: monalisa — binned_motif_enrichment
// Identify enriched motifs in genomic regions grouped into multiple bins based on a continuous numerical value (e.g., methylation changes).
// Input: peaks.bed, methylation_changes.tsv, motifs.jaspar
// Container: quay.io/biocontainers/bioconductor-monalisa:1.16.0--r45hdfd78af_0
// R packages: BSgenome.Mmusculus.UCSC.mm10, GenomicRanges, Biostrings, circlize, ComplexHeatmap, JASPAR2020, monaLisa, rtracklayer, SummarizedExperiment, TFBSTools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: heatmap, cluster plot

nextflow.enable.dsl = 2

process BIOC_MONALISA_BINNED_MOTIF_ENRICHMENT {
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
    .bm_deps <- c("BSgenome.Mmusculus.UCSC.mm10", "GenomicRanges", "Biostrings", "circlize", "ComplexHeatmap", "JASPAR2020", "monaLisa", "rtracklayer", "SummarizedExperiment", "TFBSTools")
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
    library(GenomicRanges)
    library(SummarizedExperiment)
    library(TFBSTools)
    library(BSgenome.Mmusculus.UCSC.mm10)
    library(monaLisa)
    library(ComplexHeatmap)
    library(circlize)
    library(rtracklayer)
    
    # ==========================================
    # --- Load genomic regions and select subset ---
    # ==========================================
    
    if (!file.exists("peaks.bed")) {
        stop("Required input file 'peaks.bed' not found in the working directory.")
    }
    if (!file.exists("methylation_changes.tsv")) {
        stop("Required input file 'methylation_changes.tsv' not found in the working directory.")
    }
    if (!file.exists("motifs.jaspar")) {
        stop("Required input file 'motifs.jaspar' not found in the working directory.")
    }
    
    # Read genomic regions from BED file
    lmr <- rtracklayer::import(con = "peaks.bed", format = "bed")
    
    # Read methylation changes and associate with the peaks
    meth_data <- read.delim("methylation_changes.tsv", header = TRUE, sep = "\t")
    
    if ("deltaMeth" %in% colnames(meth_data)) {
        lmr\$deltaMeth <- meth_data\$deltaMeth
    } else {
        # Fallback to the first numeric column if 'deltaMeth' is not explicitly named
        numeric_cols <- sapply(meth_data, is.numeric)
        if (any(numeric_cols)) {
            lmr\$deltaMeth <- meth_data[[which(numeric_cols)[1]]]
        } else {
            stop("No numeric column found in 'methylation_changes.tsv' to use as deltaMeth.")
        }
    }
    
    # Select subset of genomic regions
    set.seed(1)
    sample_size <- min(10000, length(lmr))
    lmrsel <- lmr[ sample(x = length(lmr), size = sample_size, replace = FALSE) ]
    
    # ==========================================
    # --- Bin genomic regions based on numerical values ---
    # ==========================================
    
    bins <- bin(x = lmrsel\$deltaMeth, binmode = "equalN", nElement = 800, minAbsX = 0.3)
    
    # Save binning information
    write.csv(as.data.frame(table(bins)), "bin_counts.csv", row.names = FALSE)
    
    # ==========================================
    # --- Prepare motifs (get PFMs and convert to PWMs) ---
    # ==========================================
    
    # Read PFMs from the user-provided JASPAR file
    pfms <- TFBSTools::readJASPARMatrix("motifs.jaspar", matrixClass = "PFM")
    pwms <- TFBSTools::toPWM(pfms)
    
    # ==========================================
    # --- Resize genomic regions and extract sequences ---
    # ==========================================
    
    lmrsel <- trim(resize(lmrsel, width = median(width(lmrsel)), fix = "center"))
    lmrseqs <- getSeq(BSgenome.Mmusculus.UCSC.mm10, lmrsel)
    
    # ==========================================
    # --- Run diagnostics on sequence composition ---
    # ==========================================
    
    pdf("plot_bin_diagnostics_GCfrac.pdf", width = 7, height = 5)
    plotBinDiagnostics(seqs = lmrseqs, bins = bins, aspect = "GCfrac")
    dev.off()
    
    pdf("plot_bin_diagnostics_dinucfreq.pdf", width = 8, height = 6)
    plotBinDiagnostics(seqs = lmrseqs, bins = bins, aspect = "dinucfreq")
    dev.off()
    
    # ==========================================
    # --- Run binned motif enrichment ---
    # ==========================================
    
    se <- calcBinnedMotifEnrR(seqs = lmrseqs, bins = bins, pwmL = pwms)
    
    # Manually populate the motif.pfm metadata to ensure downstream motifSimilarity works
    rowData(se)\$motif.pfm <- pfms[rownames(se)]
    
    # Save the complete SummarizedExperiment object
    saveRDS(se, "binned_motif_enrichment_results.rds")
    
    # Export raw enrichment values to CSV
    write.csv(as.data.frame(assay(se, "log2enr")), "motif_log2_enrichment.csv")
    write.csv(as.data.frame(assay(se, "negLog10Padj")), "motif_negLog10Padj.csv")
    
    # ==========================================
    # --- Filter and plot results ---
    # ==========================================
    
    sel <- apply(assay(se, "negLog10Padj"), 1, function(x) max(abs(x), 0, na.rm = TRUE)) > 4.0
    seSel <- se[sel, ]
    
    # Save selected enriched motifs
    saveRDS(seSel, "selected_enriched_motifs.rds")
    
    if (nrow(seSel) > 0) {
        pdf("motif_heatmaps_clustered_default.pdf", width = 8, height = 10)
        tryCatch({
            plotMotifHeatmaps(x = seSel, which.plots = c("log2enr", "negLog10Padj"), width = 2.0, cluster = TRUE, maxEnr = 2, maxSig = 10, show_motif_GC = TRUE)
        }, error = function(e) {
            message("Could not generate default clustered heatmap: ", e\$message)
        })
        dev.off()
    }
    
    # ==========================================
    # --- Cluster motifs by similarity and plot ---
    # ==========================================
    
    if (nrow(seSel) > 1) {
        SimMatSel <- motifSimilarity(rowData(seSel)\$motif.pfm)
        hcl <- hclust(as.dist(1 - SimMatSel), method = "average")
        
        pdf("motif_heatmaps_clustered_similarity.pdf", width = 10, height = 12)
        tryCatch({
            plotMotifHeatmaps(x = seSel, which.plots = c("log2enr", "negLog10Padj"), width = 1.8, cluster = hcl, maxEnr = 2, maxSig = 10, show_dendrogram = TRUE, show_seqlogo = TRUE, width.seqlogo = 1.2)
        }, error = function(e) {
            message("Could not generate similarity-clustered heatmap: ", e\$message)
        })
        dev.off()
    } else if (nrow(seSel) == 1) {
        pdf("motif_heatmaps_single.pdf", width = 8, height = 6)
        tryCatch({
            plotMotifHeatmaps(x = seSel, which.plots = c("log2enr", "negLog10Padj"), width = 1.8, cluster = FALSE, maxEnr = 2, maxSig = 10, show_dendrogram = FALSE, show_seqlogo = TRUE, width.seqlogo = 1.2)
        }, error = function(e) {
            message("Could not generate single motif heatmap: ", e\$message)
        })
        dev.off()
    } else {
        message("No motifs met the significance threshold (negLog10Padj > 4.0). Skipping clustering plots.")
    }

    writeLines(c(
        '"BIOC_MONALISA_BINNED_MOTIF_ENRICHMENT":',
        paste0('        monalisa: ', as.character(packageVersion("monalisa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binned_motif_enrichment.csv versions.yml
    """
}

workflow BIOC_MONALISA_BINNED_MOTIF_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks.bed, methylation_changes.tsv, motifs.jaspar ] ]

    main:
    BIOC_MONALISA_BINNED_MOTIF_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MONALISA_BINNED_MOTIF_ENRICHMENT.out.tables
    plots    = BIOC_MONALISA_BINNED_MOTIF_ENRICHMENT.out.plots
    objects  = BIOC_MONALISA_BINNED_MOTIF_ENRICHMENT.out.objects
    versions = BIOC_MONALISA_BINNED_MOTIF_ENRICHMENT.out.versions
}
