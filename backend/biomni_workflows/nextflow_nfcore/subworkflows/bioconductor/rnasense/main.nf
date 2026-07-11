#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RNAsense — time_resolved_rnaseq_analysis
// Compare RNA-seq time curves between two conditions to identify differential expression and expression switches over time.
// Input: SummarizedExperiment
// Container: quay.io/biocontainers/bioconductor-rnasense:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RNAsense, SummarizedExperiment, ggplot2
// Visualizations: volcano plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and filter data
//  * 2. [Core Analysis] Perform fold change analysis at each time point
//  * 3. [Core Analysis] Detect expression switches over time
//  * 4. [Core Analysis] Combine fold change and switch results
//  * 5. [Visualization & Output] Visualize stage-specific gene sets
//  * 6. [Visualization & Output] Export results to text files

nextflow.enable.dsl = 2

process BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("RNAsense", "ggplot2", "SummarizedExperiment")
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
    library(RNAsense)
    library(SummarizedExperiment)
    library(ggplot2)
    
    # ==========================================
    # 1. Load and filter data
    # ==========================================
    
    # Read the user-provided SummarizedExperiment object
    input_file <- "summarized_experiment.rds"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    mydata <- readRDS(input_file)
    
    # Ensure the object is a SummarizedExperiment
    if (!inherits(mydata, "SummarizedExperiment")) {
      stop("Error: The input file must contain a SummarizedExperiment object.")
    }
    
    # Define analysis parameters dynamically from the data
    analyzeConditions <- unique(as.character(colData(mydata)\$condition))
    thCount <- 100
    nrcores <- 1
    
    # Set cores to 1 on Windows to avoid parallelization issues
    if (Sys.info()[[1]] == "Windows") {
      nrcores <- 1
    }
    
    # Filter out low-expression genes
    vec2Keep <- which(vapply(1:dim(mydata)[1], function(i) {
      !Reduce("&", assays(mydata)[[1]][i, ] < thCount)
    }, TRUE))
    mydata <- mydata[vec2Keep, ]
    
    # Get unique sorted measurement times from input data
    times <- unique(sort(as.numeric(colData(mydata)\$time)))
    
    # ==========================================
    # 2. Perform fold change analysis at each time point
    # ==========================================
    
    resultFC <- getFC(dataset = mydata, 
                      myanalyzeConditions = analyzeConditions, 
                      cores = nrcores, 
                      mytimes = times)
    
    # Save fold change results
    write.csv(resultFC, file = "result_fold_change.csv", row.names = FALSE)
    
    # Visualize fold change results (Volcano Plot)
    volcano_plot <- ggplot(subset(resultFC, FCdetect != "none"), 
                           aes(x = logFoldChange, y = -log10(pValue), color = FCdetect)) + 
      xlab("log2(Fold Change)") + 
      geom_point(shape = 20)
    
    ggsave("volcano_plot.pdf", plot = volcano_plot, width = 7, height = 4.5)
    
    # ==========================================
    # 3. Detect expression switches over time
    # ==========================================
    
    resultSwitch <- getSwitch(dataset = mydata,
                              experimentStepDetection = analyzeConditions[1],
                              cores = nrcores,
                              mytimes = times)
    
    # Save switch detection results
    write.csv(resultSwitch, file = "result_switch.csv", row.names = FALSE)
    
    # ==========================================
    # 4. Combine fold change and switch results
    # ==========================================
    
    resultCombined <- combineResults(resultSwitch, resultFC)
    saveRDS(resultCombined, file = "result_combined.rds")
    
    # ==========================================
    # 5. Visualize stage-specific gene sets
    # ==========================================
    
    pdf("ssgs_heatmap.pdf", width = 7, height = 5)
    plotSSGS(resultCombined, times[-length(times)])
    dev.off()
    
    # ==========================================
    # 6. Export results to text files
    # ==========================================
    
    # This function automatically writes 5 text files to the working directory:
    # - geneNamelist_switchUp.txt
    # - geneNamelist_switchDown.txt
    # - genelist_switchUp.txt
    # - genelist_switchDown.txt
    # - switchList.txt
    outputGeneTables(resultCombined)
    
    message("Pipeline completed successfully. Outputs generated in the working directory.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
    for (.cn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
    for (.dsf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS":',
        paste0('    RNAsense: ', as.character(packageVersion('RNAsense')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_time_resolved_rnaseq_analysis.csv versions.yml
    """
}

workflow BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SummarizedExperiment ] ]

    main:
    BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS.out.tables
    plots    = BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS.out.plots
    objects  = BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS.out.objects
    versions = BIOC_RNASENSE_TIME_RESOLVED_RNASEQ_ANALYSIS.out.versions
}
