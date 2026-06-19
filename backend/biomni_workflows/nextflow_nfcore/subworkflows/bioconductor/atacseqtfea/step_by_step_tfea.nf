#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ATACseqTFEA — step_by_step_tfea
// Perform transcription factor enrichment analysis step-by-step to allow parameter tuning at intermediate stages.
// Input: bamExp.bam, bamCtl.bam, bindingSites.granges
// Container: quay.io/biocontainers/bioconductor-atacseqtfea:1.12.0--r45hdfd78af_0
// R packages: ATACseqTFEA, GenomicRanges, Rsamtools, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: ATACseqTFEA, GenomicRanges, Rsamtools, Tal1, ggplot2
// Visualizations: enrichment plot
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Expand binding sites to define proximal and distal regions using expandBindingSites
//  * 2. [Core Analysis] Count 5' ends of reads in the defined regions using count5ends
//  * 3. [Core Analysis] Filter low-count binding sites using eventsFilter
//  * 4. [Core Analysis] Normalize counts to count per base (CPB) using countsNormalization
//  * 5. [Core Analysis] Calculate weighted binding scores using getWeightedBindingScore
//  * 6. [Core Analysis] Perform differential binding analysis using DBscore
//  * 7. [Core Analysis] Run TF enrichment analysis using doTFEA
//  * 8. [Visualization & Output] Plot enrichment scores using plotES

nextflow.enable.dsl = 2

process BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("ATACseqTFEA", "GenomicRanges", "Rsamtools", "ggplot2")
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
        library(ATACseqTFEA)
        library(GenomicRanges)
        library(Rsamtools)
        library(ggplot2)
        
        # 1. Load User Inputs
        message("Loading user inputs...")
        bindingSites <- readRDS("bindingSites.granges")
        
        # Define BAM files by parsing a comma-separated string to allow multiple biological replicates
        args <- commandArgs(trailingOnly = TRUE)
        if (length(args) >= 2) {
          bamExp_str <- args[1]
          bamCtl_str <- args[2]
        } else {
          bamExp_str <- "bamExp.bam"
          bamCtl_str <- "bamCtl.bam"
        }
        
        bamExp <- trimws(unlist(strsplit(bamExp_str, ",")))
        bamCtl <- trimws(unlist(strsplit(bamCtl_str, ",")))
        
        # Ensure BAM files are indexed
        message("Checking BAM index files...")
        for (bam in c(bamExp, bamCtl)) {
          if (!file.exists(paste0(bam, ".bai"))) {
            Rsamtools::indexBam(bam)
          }
        }
        
        # 2. Step-by-step TFEA Workflow
        
        # Stage 1: Expand binding sites to define proximal and distal regions
        message("Expanding binding sites...")
        exbs <- expandBindingSites(bindingSites=bindingSites,
                                   proximal=40,
                                   distal=40,
                                   gap=10)
        
        # Stage 2: Count 5' ends of reads in the defined regions
        message("Counting 5' ends...")
        counts <- count5ends(bam=c(bamExp, bamCtl),
                             positive=0L, negative=0L,
                             bindingSites = bindingSites,
                             bindingSitesWithGap=exbs\$bindingSitesWithGap,
                             bindingSitesWithProximal=exbs\$bindingSitesWithProximal,
                             bindingSitesWithProximalAndGap=
                                 exbs\$bindingSitesWithProximalAndGap,
                             bindingSitesWithDistal=exbs\$bindingSitesWithDistal)
        
        # Stage 3: Filter low-count binding sites
        message("Filtering counts...")
        print(colnames(counts))
        counts <- eventsFilter(counts, "proximalRegion>0")
        
        # Stage 4: Normalize counts to count per base (CPB)
        message("Normalizing counts...")
        counts <- countsNormalization(counts, proximal=40, distal=40)
        
        # Stage 5: Calculate weighted binding scores
        message("Calculating weighted binding scores...")
        counts <- getWeightedBindingScore(counts)
        
        # Stage 6: Perform differential binding analysis
        message("Performing differential binding analysis...")
        n_exp <- length(bamExp)
        n_ctl <- length(bamCtl)
        design <- cbind(CTL=1, EXPvsCTL=c(rep(1, n_exp), rep(0, n_ctl)))
        counts <- DBscore(counts, design=design, coef="EXPvsCTL")
        
        # Stage 7: Run TF enrichment analysis
        message("Running TF enrichment analysis...")
        res <- doTFEA(counts)
        print(res)
        
        # Stage 8: Plot enrichment scores
        message("Plotting enrichment scores...")
        # Determine TF to plot (use the top TF from results, or default if empty)
        if (!is.null(res\$resultsTable) && nrow(res\$resultsTable) > 0) {
          TF <- res\$resultsTable\$TF[1]
        } else {
          TF <- "Tal1::Gata1"
        }
        
        p <- plotES(res, TF=TF, outfolder=NA)
        
        # Save outputs
        message("Saving outputs...")
        write.csv(res\$resultsTable, "tfea_results.csv", row.names=FALSE)
        saveRDS(res, "tfea_results.rds")
        
        if (!is.null(p)) {
          ggplot2::ggsave("enrichment_score_plot.pdf", plot = p, width = 7, height = 5)
        }
        
        message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA":',
        paste0('    ATACseqTFEA: ', as.character(packageVersion('ATACseqTFEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_tfea.csv versions.yml
    """
}

workflow BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamExp.bam, bamCtl.bam, bindingSites.granges ] ]

    main:
    BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA(ch_input)

    emit:
    tables   = BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA.out.tables
    plots    = BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA.out.plots
    objects  = BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA.out.objects
    versions = BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA.out.versions
}
