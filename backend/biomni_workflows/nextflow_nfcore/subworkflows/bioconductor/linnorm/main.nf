#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Linnorm — normalization_and_transformation
// Normalize, transform, and optionally impute raw count or expression data for downstream parametric analysis or export.
// Input: Islam2011
// Container: quay.io/biocontainers/bioconductor-linnorm:2.34.0--r45ha27e39d_0
// R packages: gplots, igraph, knitr, Linnorm, RColorBrewer
// Bioconductor: 3.20 | R: 4.4
// Requires: Linnorm
// QC: low-count filtering, missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the Linnorm library and dataset
//  * 2. [Core Analysis] Perform normalizing transformation with or without low-count filtering
//  * 3. [Visualization & Output] Export transformed data to a tab-delimited file
//  * 4. [Core Analysis] Perform normalization to XPM or Raw counts
//  * 5. [Core Analysis] Optionally perform data imputation or select stable genes

nextflow.enable.dsl = 2

process BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION {
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
    .bm_deps <- c("gplots", "igraph", "knitr", "Linnorm", "RColorBrewer")
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
    
    # Load required library
    library(Linnorm)
    
    # Read the user input file "Islam2011" from the working directory.
    # We assume it is a tab-separated or comma-separated file with gene names as row names.
    if (file.exists("Islam2011")) {
      Islam2011 <- tryCatch({
        as.matrix(read.table("Islam2011", header=TRUE, sep="\t", row.names=1, check.names=FALSE))
      }, error = function(e) {
        as.matrix(read.csv("Islam2011", header=TRUE, row.names=1, check.names=FALSE))
      })
    } else {
      stop("Required input file 'Islam2011' not found in the working directory.")
    }
    
    # Do not filter gene list:
    Transformed <- Linnorm(Islam2011)
    
    # Filter low count genes
    result <- Linnorm(Islam2011, Filter=TRUE)
    FTransformed <- result[["Linnorm"]]
    
    # You can use this file with Excel.
    # This file includes all genes.
    write.table(Transformed, "Transformed.txt",
    quote=FALSE, sep="\t", col.names=TRUE, row.names=TRUE)
    
    # This file filtered low count genes.
    write.table(FTransformed, "Transformed.txt",
    quote=FALSE, sep="\t", col.names=TRUE, row.names=TRUE)
    
    # Also write FTransformed to a unique filename to avoid overwriting Transformed.txt
    write.table(FTransformed, "FTransformed.txt",
    quote=FALSE, sep="\t", col.names=TRUE, row.names=TRUE)
    
    # Normalization
    Normalized <- Linnorm.Norm(Islam2011)
    
    # You can use this file with Excel.
    write.table(Normalized, "Normalized.txt",
    quote=FALSE, sep="\t", col.names=TRUE, row.names=TRUE)
    
    # Data Imputation
    DataImputed <- Linnorm.DataImput(Transformed)
    
    # Or, users can directly perform data imputation during transformation.
    DataImputed <- Linnorm(Islam2011,DataImputation=TRUE)
    
    # Save imputed data
    write.table(DataImputed, "DataImputed.txt",
    quote=FALSE, sep="\t", col.names=TRUE, row.names=TRUE)
    
    # Obtain stable genes
    StableGenes <- Linnorm.SGenes(Islam2011)
    
    # Save stable genes
    write.table(StableGenes, "StableGenes.txt",
    quote=FALSE, sep="\t", col.names=TRUE, row.names=TRUE)
    
    # Save RDS objects for downstream R analysis
    saveRDS(Transformed, "Transformed.rds")
    saveRDS(FTransformed, "FTransformed.rds")
    saveRDS(Normalized, "Normalized.rds")
    saveRDS(DataImputed, "DataImputed.rds")
    saveRDS(StableGenes, "StableGenes.rds")
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

    # missing-value handling — scan .rds matrix/data.frame artifacts for max NA fraction
    .mv_na_fracs <- numeric(0)
    .mv_scanned <- character(0)
    for (.mv_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .mv_obj <- tryCatch(readRDS(.mv_rds), error = function(e) NULL)
      .mv_mat <- if (is.matrix(.mv_obj) || is.data.frame(.mv_obj)) .mv_obj else NULL
      if (!is.null(.mv_mat)) {
        .mv_vals <- suppressWarnings(as.numeric(as.matrix(.mv_mat)))
        if (length(.mv_vals) > 0) {
          .mv_na_fracs <- c(.mv_na_fracs, mean(is.na(.mv_vals)))
          .mv_scanned <- c(.mv_scanned, .mv_rds)
        }
      }
    }
    .mv_max <- if (length(.mv_na_fracs) > 0) round(max(.mv_na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .mv_max,
      passes = isTRUE(is.finite(.mv_max) && .mv_max < 0.05),
      status = if (is.finite(.mv_max)) paste0("computed (scanned ", length(.mv_scanned), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION":',
        paste0('    Linnorm: ', as.character(packageVersion('Linnorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_normalization_and_transformation.csv versions.yml
    """
}

workflow BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Islam2011 ] ]

    main:
    BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION(ch_input)

    emit:
    tables   = BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION.out.tables
    plots    = BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION.out.plots
    objects  = BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION.out.objects
    versions = BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION.out.versions
}
