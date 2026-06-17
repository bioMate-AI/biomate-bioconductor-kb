#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ChIPseqR — nucleosome_calling_and_analysis
// Identify nucleosome positioning and binding sites from mapped ChIP-seq reads, estimate parameters, and visualize results.
// Input: reads.csv
// Container: quay.io/biocontainers/bioconductor-chipseqr:1.64.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ChIPseqR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Pile up reads to count strand-specific coverage using strandPileup
//  * 2. [Core Analysis] Estimate binding and support region lengths using getBindLen
//  * 3. [Core Analysis] Call nucleosomes and identify binding sites using simpleNucCall
//  * 4. [Visualization & Output] Plot diagnostic distributions to assess the null model
//  * 5. [Core Analysis] Extract predicted peaks and filter overlapping predictions
//  * 6. [Visualization & Output] Visualize read counts and predicted binding sites in a genomic window
//  * 7. [Core Analysis] Decompress data if needed for downstream analysis

nextflow.enable.dsl = 2

process BIOC_CHIPSEQR_NUCLEOSOME_CALLING_AND_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("ChIPseqR")
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
        library(ChIPseqR)
        
        # Read user input file
        if (!file.exists("reads.csv")) {
          stop("Error: 'reads.csv' not found in the working directory.")
        }
        
        reads <- read.csv("reads.csv", stringsAsFactors = FALSE)
        
        # Initialize 'pos' to an empty numeric vector to prevent "object not found" errors
        # during the abline call if true simulated positions are not available.
        pos <- numeric(0)
        
        # 1. Pile up reads to count strand-specific coverage
        chr_len <- max(reads\$position) + 10000
        counts <- strandPileup(reads, chrLen=chr_len, extend=1, plot=FALSE)
        
        # 2. Estimate binding and support region lengths
        bLen <- getBindLen(counts, bind = c(100,200), support = c(5, 50))
        saveRDS(bLen, "binding_length_estimate.rds")
        
        # 3. Call nucleosomes and identify binding sites
        nucs <- simpleNucCall(counts, bind=147, support=15, plot=FALSE)
        saveRDS(nucs, "nucleosome_calls.rds")
        
        # Open PDF device for diagnostic and visualization plots
        pdf("nucleosome_analysis_plots.pdf", width=10, height=8)
        
        # 4. Plot diagnostic distributions to assess the null model
        tryCatch({
          plot(nucs, type="density")
        }, error = function(e) {
          warning("Failed to plot density: ", e\$message)
        })
        
        tryCatch({
          plot(nucs, type="qqplot")
        }, error = function(e) {
          warning("Failed to plot qqplot: ", e\$message)
        })
        
        # 5. Extract predicted peaks and filter overlapping predictions
        # 6. Visualize read counts and predicted binding sites in a genomic window
        tryCatch({
          target_chr <- names(peaks(nucs))[1]
          predicted <- peaks(nucs)[[1]][1]
          plot(counts, chr=target_chr, center=predicted, score=nucs, width=1000, type="window")
          abline(v=pos[pos < predicted + 1000 & pos > predicted - 1000], col=3, lty=3)
        }, error = function(e) {
          warning("Failed to plot genomic window: ", e\$message)
        })
        
        # Close PDF device
        dev.off()
        
        # Filter overlapping predictions
        tryCatch({
          calls <- peaks(nucs)[[1]][c(1,which(diff(peaks(nucs)[[1]]) >= 170)+1)]
          length(calls)
          write.csv(data.frame(PeakPosition = calls), "predicted_nucleosomes.csv", row.names=FALSE)
        }, error = function(e) {
          warning("Failed to filter overlapping predictions: ", e\$message)
        })
        
        # 7. Decompress data if needed for downstream analysis
        counts2 <- decompress(counts)
        saveRDS(counts2, "decompressed_counts.rds")

    writeLines(c(
        '"BIOC_CHIPSEQR_NUCLEOSOME_CALLING_AND_ANALYSIS":',
        paste0('    ChIPseqR: ', as.character(packageVersion('ChIPseqR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nucleosome_calling_and_analysis.csv versions.yml
    """
}

workflow BIOC_CHIPSEQR_NUCLEOSOME_CALLING_AND_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reads.csv ] ]

    main:
    BIOC_CHIPSEQR_NUCLEOSOME_CALLING_AND_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CHIPSEQR_NUCLEOSOME_CALLING_AND_ANALYSIS.out.tables
    plots    = BIOC_CHIPSEQR_NUCLEOSOME_CALLING_AND_ANALYSIS.out.plots
    objects  = BIOC_CHIPSEQR_NUCLEOSOME_CALLING_AND_ANALYSIS.out.objects
    versions = BIOC_CHIPSEQR_NUCLEOSOME_CALLING_AND_ANALYSIS.out.versions
}
