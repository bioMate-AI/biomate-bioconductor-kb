#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeoTcgaData — dna_methylation_differential_analysis
// Identify differentially methylated genes from CpG methylation data.
// Input: cpgData, sampleGroup, cpg2gene
// Container: quay.io/biocontainers/bioconductor-geotcgadata:2.10.0--r45hdfd78af_0
// R packages: ChAMP, GeoTcgaData, S4Vectors, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: ChAMP, GeoTcgaData, S4Vectors, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare CpG methylation matrix, sample groups, and CpG-to-gene mapping
//  * 2. [Core Analysis] Run differential_methy to identify differentially methylated genes

nextflow.enable.dsl = 2

process BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS {
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
    .bm_deps <- c("ChAMP", "GeoTcgaData", "S4Vectors", "SummarizedExperiment")
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
    library(GeoTcgaData)
    library(SummarizedExperiment)
    library(ChAMP)
    library(S4Vectors)
    
    # 1. Prepare CpG methylation matrix, sample groups, and CpG-to-gene mapping
    # Read inputs from the working directory
    
    # Load cpgData (can be a matrix or a SummarizedExperiment)
    if (file.exists("cpgData.rds")) {
      cpgData <- readRDS("cpgData.rds")
    } else if (file.exists("cpgData.csv")) {
      cpgData <- as.matrix(read.csv("cpgData.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: cpgData file not found. Please provide 'cpgData.rds' or 'cpgData.csv' in the working directory.")
    }
    
    # Load sampleGroup (vector of sample group assignments)
    if (file.exists("sampleGroup.rds")) {
      sampleGroup <- readRDS("sampleGroup.rds")
    } else if (file.exists("sampleGroup.csv")) {
      sg_df <- read.csv("sampleGroup.csv", header = TRUE)
      if (ncol(sg_df) >= 2) {
        sampleGroup <- sg_df[[2]]
        names(sampleGroup) <- sg_df[[1]]
      } else {
        sampleGroup <- sg_df[[1]]
        if (!is.null(rownames(sg_df)) && !all(rownames(sg_df) == as.character(seq_len(nrow(sg_df))))) {
          names(sampleGroup) <- rownames(sg_df)
        }
      }
    } else {
      stop("Error: sampleGroup file not found. Please provide 'sampleGroup.rds' or 'sampleGroup.csv' in the working directory.")
    }
    
    # Load cpg2gene (data frame mapping CpG probe IDs to gene symbols)
    if (file.exists("cpg2gene.rds")) {
      cpg2gene <- readRDS("cpg2gene.rds")
    } else if (file.exists("cpg2gene.csv")) {
      cpg2gene <- read.csv("cpg2gene.csv", header = TRUE)
    } else {
      stop("Error: cpg2gene file not found. Please provide 'cpg2gene.rds' or 'cpg2gene.csv' in the working directory.")
    }
    
    # 2. Run differential_methy to identify differentially methylated genes
    if (inherits(cpgData, "SummarizedExperiment")) {
      # Align sampleGroup with SummarizedExperiment colData if names are available
      if (!is.null(names(sampleGroup))) {
        common_samples <- intersect(colnames(cpgData), names(sampleGroup))
        if (length(common_samples) > 0) {
          cpgData <- cpgData[, common_samples]
          sampleGroup <- sampleGroup[common_samples]
        }
      }
      
      # Ensure the group column is present in colData
      SummarizedExperiment::colData(cpgData)\$group <- sampleGroup
      
      # Run using SummarizedExperiment input
      result <- differential_methy(cpgData = cpgData, 
                                   groupCol = "group", 
                                   normMethod = NULL, 
                                   cpg2gene = cpg2gene)
    } else {
      # Align sampleGroup with matrix columns if names are available
      if (!is.null(names(sampleGroup))) {
        common_samples <- intersect(colnames(cpgData), names(sampleGroup))
        if (length(common_samples) > 0) {
          cpgData <- cpgData[, common_samples, drop = FALSE]
          sampleGroup <- sampleGroup[common_samples]
        }
      } else {
        if (length(sampleGroup) == ncol(cpgData)) {
          names(sampleGroup) <- colnames(cpgData)
        }
      }
      
      # Run using matrix input
      result <- differential_methy(cpgData, 
                                   sampleGroup, 
                                   cpg2gene = cpg2gene, 
                                   normMethod = NULL)
    }
    
    # 3. Write outputs
    saveRDS(result, "differential_methylation_results.rds")
    
    if (is.data.frame(result)) {
      write.csv(result, "differential_methylation_results.csv", row.names = TRUE)
    } else if (is.list(result)) {
      for (name in names(result)) {
        if (is.data.frame(result[[name]]) || is.matrix(result[[name]])) {
          write.csv(result[[name]], paste0("differential_methylation_results_", name, ".csv"), row.names = TRUE)
        }
      }
    }
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # array detection QC — ExpressionSet detection p-values or detection-column data.frame.
    .adq_rate <- NA_real_
    for (.adq_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .adq_obj <- tryCatch(readRDS(.adq_rds), error = function(e) NULL)
      .adq_pv <- NULL
      if (!is.null(.adq_obj)) {
        if (inherits(.adq_obj, "ExpressionSet")) {
          .adq_pv <- tryCatch(Biobase::assayDataElement(.adq_obj, "Detection"), error = function(e) NULL)
        } else if (is.matrix(.adq_obj) || is.data.frame(.adq_obj)) {
          .adq_cols <- grep("(?i)(detection|pvalue|pval)", colnames(.adq_obj), value = TRUE)
          if (length(.adq_cols) > 0) .adq_pv <- as.matrix(.adq_obj[, .adq_cols, drop = FALSE])
        }
      }
      if (!is.null(.adq_pv) && length(.adq_pv) > 0) {
        .adq_rate <- round(mean(as.numeric(.adq_pv) < 0.05, na.rm = TRUE), 4); break
      }
    }
    .gates_by_label[["array detection QC"]] <- list(
      gate_row = "bioc_array_detection_qc",
      metric_name = "detection_rate",
      metric_value = .adq_rate,
      passes = isTRUE(is.finite(.adq_rate) && .adq_rate >= 0.75),
      status = if (is.finite(.adq_rate)) "computed (probe-detection p<0.05 fraction)"
               else "not_computed (no ExpressionSet/detection-p .rds present)"
    )

    # alignment/mapping QC — workflow-emitted artifact check for common log
    # files (.log, .summary, alignment metrics tables). Binary pass.
    .amqc_logs <- c(list.files(".", pattern = "(?i)(align|map|samtools|flagstat).*\\.(log|txt|summary)\$"),
                    list.files(".", pattern = "(?i)flagstat\\."))
    .amqc_passes <- length(.amqc_logs) > 0
    .gates_by_label[["alignment/mapping QC"]] <- list(
      gate_row = "bioc_alignment_mapping_qc",
      metric_name = "alignment_qc_artifacts",
      metric_value = length(.amqc_logs),
      passes = .amqc_passes,
      status = if (.amqc_passes) paste0("computed (", length(.amqc_logs), " alignment log(s) emitted)")
               else "not_computed (no alignment log/summary artifact present)"
    )

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("array detection QC", "alignment/mapping QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS":',
        paste0('    GeoTcgaData: ', as.character(packageVersion('GeoTcgaData')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dna_methylation_differential_analysis.csv versions.yml
    """
}

workflow BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cpgData, sampleGroup, cpg2gene ] ]

    main:
    BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS.out.tables
    plots    = BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS.out.plots
    objects  = BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS.out.objects
    versions = BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS.out.versions
}
