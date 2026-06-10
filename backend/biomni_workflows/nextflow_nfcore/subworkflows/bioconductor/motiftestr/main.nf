#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifTestR — positional_bias_analysis
// Identify transcription factor binding motifs that show positional bias (localization) relative to the centers of a set of genomic sequences.
// Input: ar_er_peaks, BSgenome.Hsapiens.UCSC.hg19, ex_pfm
// Container: quay.io/biocontainers/bioconductor-motiftestr:1.6.1--r45hdfd78af_0
// R packages: BSgenome, BSgenome.Hsapiens.UCSC.hg19, GenomicRanges, extraChIPs, ggplot2, motifTestR, patchwork, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome, BSgenome.Hsapiens.UCSC.hg19, GenomicRanges, ggplot2, motifTestR, patchwork
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract sequences from genomic peaks using getSeq()
//  * 2. [Core Analysis] Find PWM matches in the sequences using getPwmMatches()
//  * 3. [Core Analysis] Test for positional bias using testMotifPos()
//  * 4. [Visualization & Output] Visualize the positional distribution of matches using plotMatchPos()

nextflow.enable.dsl = 2

process BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("BSgenome", "BSgenome.Hsapiens.UCSC.hg19", "GenomicRanges", "extraChIPs", "ggplot2", "motifTestR", "patchwork", "rtracklayer")
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
    library(motifTestR)
    library(BSgenome)
    library(GenomicRanges)
    library(ggplot2)
    library(patchwork)
    
    # Set cores for parallel processing
    cores <- 1
    
    # Read user inputs from the working directory
    ar_er_peaks <- readRDS("ar_er_peaks.rds")
    ex_pfm <- readRDS("ex_pfm.rds")
    
    # Load BSgenome object from RDS if available, otherwise load package
    if (file.exists("BSgenome.Hsapiens.UCSC.hg19.rds")) {
      BSgenome.Hsapiens.UCSC.hg19 <- readRDS("BSgenome.Hsapiens.UCSC.hg19.rds")
    } else {
      library(BSgenome.Hsapiens.UCSC.hg19)
    }
    
    # 1. Extract sequences from genomic peaks using getSeq()
    test_seq <- getSeq(BSgenome.Hsapiens.UCSC.hg19, ar_er_peaks)
    names(test_seq) <- as.character(ar_er_peaks)
    
    # 2. Find PWM matches in the sequences using getPwmMatches()
    score_thresh <- "70%"
    if (length(ex_pfm) > 0) {
      getPwmMatches(ex_pfm[[1]], test_seq, min_score = score_thresh)
      getPwmMatches(ex_pfm[[1]], test_seq, min_score = score_thresh, best_only = TRUE)
    }
    
    bm_all <- getPwmMatches(
      ex_pfm, test_seq, min_score = score_thresh, best_only = TRUE, break_ties = "all",
      mc.cores = cores
    )
    
    counts <- countPwmMatches(ex_pfm, test_seq, min_score = score_thresh, mc.cores = cores)
    
    # 3. Test for positional bias using testMotifPos()
    res_pos <- testMotifPos(bm_all, mc.cores = cores)
    res_abs <- testMotifPos(bm_all, abs = TRUE, mc.cores = cores)
    
    # 4. Visualize the positional distribution of matches using plotMatchPos()
    topMotifs <- res_pos |>
        subset(fdr < 0.05) |>
        rownames()
    
    if (length(topMotifs) > 0) {
      A <- plotMatchPos(bm_all[topMotifs], binwidth = 10, se = FALSE)
      B <- plotMatchPos(
          bm_all[topMotifs], binwidth = 10, geom = "col", use_totals = TRUE
      ) +
        geom_smooth(se = FALSE, show.legend = FALSE) +
        facet_wrap(~name)
      
      final_plot <- A + B + plot_annotation(tag_levels = "A") & theme(legend.position = "bottom")
    }
    
    # Write outputs to the working directory
    write.csv(as.data.frame(res_pos), "res_pos.csv", row.names = TRUE)
    write.csv(as.data.frame(res_abs), "res_abs.csv", row.names = TRUE)
    saveRDS(bm_all, "bm_all.rds")
    
    if (!is.null(counts)) {
      write.csv(data.frame(motif = names(counts), count = as.vector(counts)), "match_counts.csv", row.names = FALSE)
    }
    
    if (length(topMotifs) > 0) {
      ggsave("positional_bias_plot.pdf", plot = final_plot, width = 12, height = 6)
    }

    writeLines(c(
        '"BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS":',
        paste0('    motifTestR: ', as.character(packageVersion('motifTestR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_positional_bias_analysis.csv versions.yml
    """
}

workflow BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ar_er_peaks, BSgenome.Hsapiens.UCSC.hg19, ex_pfm ] ]

    main:
    BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS.out.tables
    plots    = BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS.out.plots
    objects  = BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS.out.objects
    versions = BIOC_MOTIFTESTR_POSITIONAL_BIAS_ANALYSIS.out.versions
}
