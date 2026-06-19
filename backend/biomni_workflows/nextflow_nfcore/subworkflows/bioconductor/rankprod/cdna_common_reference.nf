#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RankProd — cdna_common_reference
// Identify differentially expressed genes from cDNA microarray data using a common reference design.
// Input: cdna_intensities.tsv
// Container: quay.io/biocontainers/bioconductor-rankprod:3.36.0--r45hdfd78af_0
// R packages: RankProd, vsn
// Bioconductor: 3.20 | R: 4.4
// Requires: RankProd, vsn
// Visualizations: plot (ggplot/base)
// QC: variance-stabilizing normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize intensities (e.g., using vsn)
//  * 2. [Core Analysis] Calculate log-ratios by subtracting reference intensities from sample intensities
//  * 3. [Core Analysis] Run RankProducts on the log-ratios with class labels
//  * 4. [Core Analysis] Extract significant genes using topGene

nextflow.enable.dsl = 2

process BIOC_RANKPROD_CDNA_COMMON_REFERENCE {
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
    .bm_deps <- c("RankProd", "vsn")
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
    library(vsn)
    library(RankProd)
    
    # 1. Read user input file
    input_file <- "cdna_intensities.tsv"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the intensities matrix (genes as rows, columns of interleaved reference/sample channels)
    intensities_matrix <- as.matrix(read.delim(input_file, row.names = 1, header = TRUE, check.names = FALSE))
    
    # 2. Normalize intensities using vsn
    lym.exp <- justvsn(intensities_matrix)
    
    # 3. Calculate log-ratios by subtracting reference intensities from sample intensities
    n_pairs <- ncol(intensities_matrix) / 2
    refrs <- (1:n_pairs)*2-1
    samps <- (1:n_pairs)*2
    M <- lym.exp[,samps]-lym.exp[,refrs]
    
    # 4. Run RankProducts on the log-ratios with class labels
    cl <- rep(1, n_pairs)
    RP.out <- RankProducts(M, cl, logged=TRUE, rand=123)
    
    # 5. Extract significant genes using topGene
    # Exact documented call:
    topGene(RP.out,cutoff=0.05,logged=TRUE,logbase=exp(1))
    
    # Capture results for saving
    res <- topGene(RP.out,cutoff=0.05,logged=TRUE,logbase=exp(1))
    
    # 6. Write named output files
    # Save the RankProducts output object
    saveRDS(RP.out, file = "rankprod_output.rds")
    
    # Save the tables of significant genes
    if (!is.null(res\$Table1)) {
      write.csv(res\$Table1, file = "significant_up_regulated.csv", row.names = TRUE)
    }
    if (!is.null(res\$Table2)) {
      write.csv(res\$Table2, file = "significant_down_regulated.csv", row.names = TRUE)
    }
    
    # Save diagnostic plots
    pdf("rankprod_plots.pdf")
    plotRP(RP.out, cutoff=0.05)
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved: rankprod_output.rds, significant_up_regulated.csv, significant_down_regulated.csv, rankprod_plots.pdf\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # VSN — DESeqTransform / vsd matrix; mean-SD slope ≤ 0.5 (vsn::meanSdPlot).
    .vsn_slope <- NA_real_
    for (.vsn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .vsn_obj <- tryCatch(readRDS(.vsn_rds), error = function(e) NULL)
      .vsn_mat <- NULL
      if (!is.null(.vsn_obj)) {
        if (inherits(.vsn_obj, "DESeqTransform") || inherits(.vsn_obj, "SummarizedExperiment")) {
          .vsn_mat <- tryCatch(assay(.vsn_obj), error = function(e) NULL)
        } else if (is.matrix(.vsn_obj)) { .vsn_mat <- .vsn_obj }
      }
      if (!is.null(.vsn_mat) && nrow(.vsn_mat) > 100) {
        .vsn_rmean <- suppressWarnings(rowMeans(.vsn_mat, na.rm = TRUE))
        .vsn_rsd <- suppressWarnings(apply(.vsn_mat, 1, sd, na.rm = TRUE))
        .vsn_ok <- is.finite(.vsn_rmean) & is.finite(.vsn_rsd)
        if (sum(.vsn_ok) > 50) {
          .vsn_fit <- tryCatch(lm(.vsn_rsd[.vsn_ok] ~ .vsn_rmean[.vsn_ok]), error = function(e) NULL)
          if (!is.null(.vsn_fit)) { .vsn_slope <- round(abs(coef(.vsn_fit)[2]), 4); break }
        }
      }
    }
    .gates_by_label[["variance-stabilizing normalization"]] <- list(
      gate_row = "bioc_vsn_normalization",
      metric_name = "mean_sd_slope_after_vsn",
      metric_value = .vsn_slope,
      passes = isTRUE(is.finite(.vsn_slope) && .vsn_slope <= 0.5),
      status = if (is.finite(.vsn_slope)) "computed (lm slope row-SD ~ row-mean)"
               else "not_computed (no DESeqTransform/vsd .rds present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_RANKPROD_CDNA_COMMON_REFERENCE",
      domain  = "bioconductor",
      declared_qc_steps = c("variance-stabilizing normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RANKPROD_CDNA_COMMON_REFERENCE":',
        paste0('    RankProd: ', as.character(packageVersion('RankProd')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cdna_common_reference.csv versions.yml
    """
}

workflow BIOC_RANKPROD_CDNA_COMMON_REFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cdna_intensities.tsv ] ]

    main:
    BIOC_RANKPROD_CDNA_COMMON_REFERENCE(ch_input)

    emit:
    tables   = BIOC_RANKPROD_CDNA_COMMON_REFERENCE.out.tables
    plots    = BIOC_RANKPROD_CDNA_COMMON_REFERENCE.out.plots
    objects  = BIOC_RANKPROD_CDNA_COMMON_REFERENCE.out.objects
    versions = BIOC_RANKPROD_CDNA_COMMON_REFERENCE.out.versions
}
