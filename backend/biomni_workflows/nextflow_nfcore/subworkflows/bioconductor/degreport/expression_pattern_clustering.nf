#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEGreport — expression_pattern_clustering
// Detect and cluster genes showing similar expression patterns across experimental groups or time points.
// Input: dds_object.rds, res_object.rds
// Container: quay.io/biocontainers/bioconductor-degreport:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DEGreport, DESeq2
// Visualizations: plot (ggplot/base)
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Save the full degPatterns output object
//  * 2. [Input & Preparation] Save the gene-to-cluster mapping table
//  * 3. [Input & Preparation] Save the plot

nextflow.enable.dsl = 2

process BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING {
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
    .bm_deps <- c("DESeq2", "DEGreport", "SummarizedExperiment")
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
    library(DESeq2)
    library(SummarizedExperiment)
    library(DEGreport)
    
    # Check if input files exist
    if (!file.exists("dds_object.rds") || !file.exists("res_object.rds")) {
      stop("Required input files 'dds_object.rds' and/or 'res_object.rds' not found in the working directory.")
    }
    
    # Read user input files
    dds <- readRDS("dds_object.rds")
    res <- readRDS("res_object.rds")
    
    # Align res and dds to ensure matching genes
    common_genes <- intersect(rownames(res), rownames(dds))
    if (length(common_genes) == 0) {
      stop("No common genes found between dds_object and res_object.")
    }
    res <- res[common_genes, ]
    dds <- dds[common_genes, ]
    
    # Extract design from dds object
    design <- as.data.frame(colData(dds))
    
    # Ensure the 'group' column exists in design (since time = "group" is used in degPatterns)
    if (!"group" %in% colnames(design)) {
      possible_groups <- c("group", "condition", "treatment", "time", "status")
      found_col <- intersect(possible_groups, colnames(design))
      if (length(found_col) > 0) {
        design\$group <- design[[found_col[1]]]
        message(paste("Using column '", found_col[1], "' as 'group' for pattern clustering.", sep = ""))
      } else {
        design\$group <- design[[1]]
        message(paste("Using first column '", colnames(design)[1], "' as 'group' for pattern clustering.", sep = ""))
      }
    }
    
    # Filter for significantly differentially expressed genes
    sig_genes <- !is.na(res\$padj) & res\$padj < 0.05
    if (any(sig_genes)) {
      res <- res[sig_genes, ]
    } else {
      # Fallback if no genes are significant: use top genes by p-value
      res <- res[order(res\$pvalue)[1:min(100, nrow(res))], ]
    }
    
    # === DOCUMENTED CODE ===
    ma = assay(rlog(dds))[row.names(res),]
    res <- degPatterns(ma, design, time = "group")
    # === END DOCUMENTED CODE ===
    
    # Save meaningful results
    # --- Save the full degPatterns output object ---
    saveRDS(res, "deg_patterns_results.rds")
    
    # --- Save the gene-to-cluster mapping table ---
    if (!is.null(res\$df)) {
      write.csv(res\$df, "expression_patterns_cl_membership.csv", row.names = FALSE)
    }
    
    # --- Save the plot ---
    if (!is.null(res\$plot)) {
      pdf("expression_patterns_plot.pdf", width = 10, height = 8)
      print(res\$plot)
      dev.off()
    }
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING":',
        paste0('    DEGreport: ', as.character(packageVersion('DEGreport')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expression_pattern_clustering.csv versions.yml
    """
}

workflow BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dds_object.rds, res_object.rds ] ]

    main:
    BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING.out.tables
    plots    = BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING.out.plots
    objects  = BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING.out.objects
    versions = BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING.out.versions
}
