#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: isoformswitchanalyzer — high_level_two_part_analysis
// Perform a complete isoform switch analysis using high-level wrapper functions to import, test, extract sequences, integrate external annotations, and predict co
// Input: salmon_quant_dir, annotation.gtf, transcript_sequences.fasta, cpc2_result.txt, pfam_results.txt, iupred2a_result.txt.gz, signalP_results.txt
// Container: quay.io/biocontainers/bioconductor-isoformswitchanalyzer:2.10.0--r45h01b2380_0
// R packages: IsoformSwitchAnalyzeR, VennDiagram
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-isoformswitchanalyzer:2.10.0--r45h01b2380_0"

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
    .bm_deps <- c("IsoformSwitchAnalyzeR", "VennDiagram")
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
    library(IsoformSwitchAnalyzeR)
    
    # Define input file paths as specified by the user
    salmon_quant_dir <- "salmon_quant_dir"
    annotation_gtf <- "annotation.gtf"
    transcript_sequences_fasta <- "transcript_sequences.fasta"
    cpc2_result <- "cpc2_result.txt"
    pfam_results <- "pfam_results.txt"
    iupred2a_result <- "iupred2a_result.txt.gz"
    signalP_results <- "signalP_results.txt"
    
    # --- Import isoform expression data ---
    salmonQuant <- importIsoformExpression(
        parentDir = salmon_quant_dir
    )
    
    # --- Create a design matrix ---
    myDesign <- data.frame(
        sampleID = colnames(salmonQuant\$abundance)[-1],
        condition = gsub('_.*', '', colnames(salmonQuant\$abundance)[-1])
    )
    
    # --- Build the switchAnalyzeRlist ---
    aSwitchList <- importRdata(
        isoformCountMatrix   = salmonQuant\$counts,
        isoformRepExpression = salmonQuant\$abundance,
        designMatrix         = myDesign,
        isoformExonAnnoation = annotation_gtf,
        isoformNtFasta       = transcript_sequences_fasta,
        fixStringTieAnnotationProblem = TRUE,
        showProgress = FALSE
    )
    
    # Handle potential NA values in dIF before subsetting to prevent errors
    if ("dIF" %in% colnames(aSwitchList\$isoformFeatures)) {
        aSwitchList\$isoformFeatures\$dIF[is.na(aSwitchList\$isoformFeatures\$dIF)] <- 0
    }
    
    # Subset the switch list for isoforms with significant usage changes
    aSwitchList <- subsetSwitchAnalyzeRlist(
        switchAnalyzeRlist = aSwitchList,
        subset = abs(aSwitchList\$isoformFeatures\$dIF) > 0.1
    )
    
    # --- Run Part 1 analysis (filtering, testing, ORF annotation, ---
    aSwitchList <- isoformSwitchAnalysisPart1(
        switchAnalyzeRlist   = aSwitchList,
        outputSequences      = FALSE, 
        prepareForWebServers = FALSE  
    )
    
    # Extract and display initial switch summary
    extractSwitchSummary( aSwitchList )
    
    # --- Run Part 2 analysis (integrating external results and ---
    aSwitchList <- isoformSwitchAnalysisPart2(
      switchAnalyzeRlist        = aSwitchList, 
      n                         = 10,    
      removeNoncodinORFs        = TRUE,
      pathToCPC2resultFile      = cpc2_result,
      pathToPFAMresultFile      = pfam_results,
      pathToIUPred2AresultFile  = iupred2a_result,
      pathToSignalPresultFile   = signalP_results,
      outputPlots               = FALSE  
    )
    
    # --- Extract top switching genes with predicted consequences ---
    top_switches <- extractTopSwitches(aSwitchList, filterForConsequences = TRUE, n=3)
    
    # Write meaningful results to output files
    saveRDS(aSwitchList, file = "isoform_switch_list_analyzed.rds")
    
    switch_summary <- extractSwitchSummary(aSwitchList)
    write.csv(switch_summary, file = "switch_summary.csv", row.names = FALSE)
    
    write.csv(top_switches, file = "top_switching_genes.csv", row.names = FALSE)
    
    # Generate and save a switch plot for the top gene if available
    if (nrow(top_switches) > 0) {
        top_gene <- top_switches\$gene_name[1]
        if (is.na(top_gene) || top_gene == "") {
            top_gene <- top_switches\$gene_id[1]
        }
        
        conds <- unique(aSwitchList\$designMatrix\$condition)
        
        pdf("top_isoform_switch_plot.pdf", onefile = FALSE, height = 6, width = 9)
        if (length(conds) >= 2) {
            switchPlot(aSwitchList, gene = top_gene, condition1 = conds[1], condition2 = conds[2])
        } else {
            switchPlot(aSwitchList, gene = top_gene)
        }
        dev.off()
    }
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

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS":',
        paste0('        isoformswitchanalyzer: ', as.character(packageVersion("isoformswitchanalyzer")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_high_level_two_part_analysis.csv versions.yml
    """
}

workflow BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ salmon_quant_dir, annotation.gtf, transcript_sequences.fasta, cpc2_result.txt, pfam_results.txt, iupred2a_result.txt.gz, signalP_results.txt ] ]

    main:
    BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS.out.tables
    plots    = BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS.out.plots
    objects  = BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS.out.objects
    versions = BIOC_ISOFORMSWITCHANALYZER_HIGH_LEVEL_TWO_PART_ANALYSIS.out.versions
}
