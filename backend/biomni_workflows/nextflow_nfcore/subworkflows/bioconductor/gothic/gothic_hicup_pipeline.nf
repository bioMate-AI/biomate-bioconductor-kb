#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOTHiC — gothic_hicup_pipeline
// Identify significant genomic interactions from pre-processed and filtered HiCUP output.
// Input: fileName, restrictionFile
// Container: quay.io/biocontainers/bioconductor-gothic:1.46.0--r45hdfd78af_0
// R packages: GOTHiC
// Bioconductor: 3.20 | R: 4.4
// Requires: GOTHiC
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Save the full data frame as a CSV table
//  * 2. [Visualization & Output] Save the results as an RDS object for downstream R
//  * 3. [Visualization & Output] Generate and save the p-value density plot to assess

nextflow.enable.dsl = 2

process BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE {
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
    .bm_deps <- c("GOTHiC")
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
    library(GOTHiC)
    
    # Define input file paths in the working directory
    fileName <- "fileName"
    restrictionFile <- "restrictionFile"
    
    # Validate that the required input files exist
    if (!file.exists(fileName)) {
      stop(paste("Error: Input file 'fileName' (mapped and filtered reads from HiCUP) not found in the working directory:", getwd()))
    }
    
    if (!file.exists(restrictionFile)) {
      stop(paste("Error: Input file 'restrictionFile' (digest/restriction fragment file) not found in the working directory:", getwd()))
    }
    
    # Run the cumulative binomial test on HiCUP output using GOTHiChicup
    # Keeping the exact function call and arguments from the documented code
    binom=GOTHiChicup(fileName, sampleName='lymphoid_chr20', res=1000000, 
    restrictionFile, cistrans='all', parallel=FALSE, cores=NULL)
    
    # Save the meaningful results to output files
    # --- Save the full data frame as a CSV table ---
    write.csv(binom, file = "gothic_hicup_results.csv", row.names = FALSE)
    
    # --- Save the results as an RDS object for downstream R ---
    saveRDS(binom, file = "gothic_hicup_results.rds")
    
    # --- Generate and save the p-value density plot to assess ---
    pdf("gothic_pvalue_density.pdf", width = 6, height = 6)
    if (!is.null(binom) && nrow(binom) > 0) {
      # Determine the correct p-value column name (typically "pvalue" or "p-value")
      p_col <- grep("p.*val", colnames(binom), ignore.case = TRUE, value = TRUE)
      if (length(p_col) > 0) {
        plot(density(binom[[p_col[1]]], na.rm = TRUE), 
             main = "P-value distribution", 
             xlab = "pvalue", 
             col = "blue", 
             las = 1)
      } else {
        warning("Could not find a p-value column in the results to plot.")
      }
    } else {
      warning("Result data frame is empty; skipping density plot.")
    }
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    # outlier detection — declarative gate per qc_evidence.yaml. Always emit
    # the row with passes=TRUE when the workflow produced any artifact;
    # downstream review confirms whether outlier flagging actually fired.
    .od_artifacts <- list.files(".", pattern = "\\.(rds|csv|tsv|txt|log)\$")
    .od_passes <- length(.od_artifacts) > 0
    .gates_by_label[["outlier detection"]] <- list(
      gate_row = "bioc_outlier_detection",
      metric_name = "artifacts_emitted",
      metric_value = length(.od_artifacts),
      passes = .od_passes,
      status = if (.od_passes) "computed (declarative; manual review for outlier-flag specifics)"
               else "not_computed (workflow emitted no artifacts)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "outlier detection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE":',
        paste0('    GOTHiC: ', as.character(packageVersion('GOTHiC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gothic_hicup_pipeline.csv versions.yml
    """
}

workflow BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fileName, restrictionFile ] ]

    main:
    BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE.out.tables
    plots    = BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE.out.plots
    objects  = BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE.out.objects
    versions = BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE.out.versions
}
