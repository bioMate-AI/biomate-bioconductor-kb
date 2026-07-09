#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: compEpiTools — genomic_region_annotation
// Annotate genomic regions of interest with proximity to nearest Transcription Start Sites (TSS), gene models, and user-defined genomic features like CpG Islands.
// Input: user_regions.RData, user_annotations.RData
// Container: quay.io/biocontainers/bioconductor-compepitools:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TxDb.Mmusculus.UCSC.mm9.knownGene, compEpiTools, org.Mm.eg.db
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define TSS positions using TSS
//  * 2. [Core Analysis] Find midpoints of genomic regions using GRmidpoint
//  * 3. [Core Analysis] Annotate regions with gene models and custom annotations using GRannotate

nextflow.enable.dsl = 2

process BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION {
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
    .bm_deps <- c("compEpiTools", "TxDb.Mmusculus.UCSC.mm9.knownGene", "org.Mm.eg.db")
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
    library(compEpiTools)
    library(TxDb.Mmusculus.UCSC.mm9.knownGene)
    library(org.Mm.eg.db)
    
    # Set up TxDb
    txdb <- TxDb.Mmusculus.UCSC.mm9.knownGene
    
    # 1. Load user input files from the working directory
    if (!file.exists("user_regions.RData")) {
      stop("Required input file 'user_regions.RData' not found in the working directory.")
    }
    if (!file.exists("user_annotations.RData")) {
      stop("Required input file 'user_annotations.RData' not found in the working directory.")
    }
    
    # Load genomic regions of interest (GRanges)
    env_regions <- new.env()
    load("user_regions.RData", envir = env_regions)
    gr_names <- names(which(sapply(env_regions, inherits, "GRanges")))
    if (length(gr_names) == 0) {
      stop("No GRanges object found in user_regions.RData")
    }
    gr <- env_regions[[gr_names[1]]]
    
    # Load custom annotations (GRangesList)
    env_ann <- new.env()
    load("user_annotations.RData", envir = env_ann)
    grl_names <- names(which(sapply(env_ann, inherits, "GRangesList")))
    if (length(grl_names) == 0) {
      stop("No GRangesList object found in user_annotations.RData")
    }
    user_ann_list <- env_ann[[grl_names[1]]]
    
    # Stage 1: Define TSS positions using TSS
    TSSpos <- TSS(txdb)
    
    # Stage 2 & 3: Find midpoints of genomic regions using GRmidpoint and annotate them using GRannotate
    # Keeping the exact function calls and argument names as documented
    res <- GRannotate(Object=GRmidpoint(gr), txdb=txdb, EG2GS=org.Mm.eg.db, 
                      upstream=2000, downstream=1000, userAnn=user_ann_list)
    
    # Display the annotated regions
    show(res)
    
    # Write outputs to the working directory
    write.csv(as.data.frame(res), file="annotated_regions.csv", row.names=FALSE)
    saveRDS(res, file="annotated_regions.rds")
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
      process = "BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION",
      domain  = "bioconductor",
      declared_qc_steps = c("array detection QC", "alignment/mapping QC", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION":',
        paste0('    compEpiTools: ', as.character(packageVersion('compEpiTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_region_annotation.csv versions.yml
    """
}

workflow BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_regions.RData, user_annotations.RData ] ]

    main:
    BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION.out.tables
    plots    = BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION.out.plots
    objects  = BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION.out.objects
    versions = BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION.out.versions
}
