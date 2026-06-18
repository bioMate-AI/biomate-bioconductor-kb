#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: monalisa — single_set_motif_enrichment
// Identify enriched motifs in a single set of sequences by comparing it to a GC-matched genomic background.
// Input: foreground_peaks.bed, motifs.jaspar
// Container: quay.io/biocontainers/bioconductor-monalisa:1.16.0--r45hdfd78af_0
// R packages: BSgenome.Mmusculus.UCSC.mm10, Biostrings, GenomicRanges, SummarizedExperiment, TFBSTools, monaLisa, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: heatmap, enrichment plot

nextflow.enable.dsl = 2

process BIOC_MONALISA_SINGLE_SET_MOTIF_ENRICHMENT {
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
    library(monaLisa)
    library(GenomicRanges)
    library(Biostrings)
    library(BSgenome.Mmusculus.UCSC.mm10)
    library(TFBSTools)
    library(rtracklayer)
    library(SummarizedExperiment)
    
    # 1. Read user input files from the working directory
    peaks <- rtracklayer::import(con = "foreground_peaks.bed", format = "bed")
    
    # Resize peaks to uniform width to avoid length bias (standard practice in monaLisa)
    peaks <- trim(resize(peaks, width = median(width(peaks)), fix = "center"))
    
    # Extract sequences for the foreground set
    lmrseqs <- Biostrings::getSeq(BSgenome.Mmusculus.UCSC.mm10, peaks)
    
    # Define dummy bins to allow exact reproduction of the documented code
    bins <- factor(rep("foreground", length(lmrseqs)))
    
    # Read motifs from JASPAR file
    pfms <- TFBSTools::readJASPARMatrix("motifs.jaspar")
    pwms <- TFBSTools::toPWM(pfms)
    
    # Create a dummy seSel to allow exact reproduction of pwms[rownames(seSel)]
    seSel <- matrix(0, nrow = length(pwms), ncol = 1)
    rownames(seSel) <- names(pwms)
    
    # --- DOCUMENTED CODE STAGE ---
    lmrseqs3 <- lmrseqs[bins == levels(bins)[1]]
    
    se3 <- calcBinnedMotifEnrR(
      seqs = lmrseqs3, 
      pwmL = pwms[rownames(seSel)], 
      background = "genome", 
      genome = BSgenome.Mmusculus.UCSC.mm10, 
      genome.regions = NULL, 
      genome.oversample = 2, 
      BPPARAM = BiocParallel::SerialParam(RNGseed = 42), 
      verbose = TRUE
    )
    
    sel3 <- assay(se3, "negLog10Padj")[, 1] > 4.0
    
    # Plot results to PDF
    pdf("motif_enrichment_heatmap.pdf", width = 8, height = 10)
    if (sum(sel3) > 0) {
      plotMotifHeatmaps(x = se3[sel3,], which.plots = c("log2enr", "negLog10Padj"), width = 1.8, maxEnr = 2, maxSig = 10, show_seqlogo = TRUE)
    } else {
      message("No motifs met the significance threshold (negLog10Padj > 4.0). Plotting all motifs instead.")
      plotMotifHeatmaps(x = se3, which.plots = c("log2enr", "negLog10Padj"), width = 1.8, maxEnr = 2, maxSig = 10, show_seqlogo = TRUE)
    }
    dev.off()
    # --- END DOCUMENTED CODE STAGE ---
    
    # Save outputs
    saveRDS(se3, "motif_enrichment_results.rds")
    
    results_df <- data.frame(
      motif_id = rownames(se3),
      motif_name = rowData(se3)\$motif.name,
      negLog10P = assay(se3, "negLog10P")[, 1],
      negLog10Padj = assay(se3, "negLog10Padj")[, 1],
      log2enr = assay(se3, "log2enr")[, 1],
      pearsonResid = assay(se3, "pearsonResid")[, 1]
    )
    write.csv(results_df, "motif_enrichment_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_MONALISA_SINGLE_SET_MOTIF_ENRICHMENT":',
        paste0('        monalisa: ', as.character(packageVersion("monalisa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_set_motif_enrichment.csv versions.yml
    """
}

workflow BIOC_MONALISA_SINGLE_SET_MOTIF_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ foreground_peaks.bed, motifs.jaspar ] ]

    main:
    BIOC_MONALISA_SINGLE_SET_MOTIF_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MONALISA_SINGLE_SET_MOTIF_ENRICHMENT.out.tables
    plots    = BIOC_MONALISA_SINGLE_SET_MOTIF_ENRICHMENT.out.plots
    objects  = BIOC_MONALISA_SINGLE_SET_MOTIF_ENRICHMENT.out.objects
    versions = BIOC_MONALISA_SINGLE_SET_MOTIF_ENRICHMENT.out.versions
}
