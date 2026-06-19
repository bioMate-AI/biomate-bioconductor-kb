#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rnits — expressionset_workflow
// Analyze time-course gene expression data starting from an ExpressionSet object.
// Input: ExpressionSet_object
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: Biobase, GEOquery, knitr, Rnits, stringr
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: missing-value handling

nextflow.enable.dsl = 2

process BIOC_RNITS_EXPRESSIONSET_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/r-base:4.3.1"

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
    .bm_deps <- c("Biobase", "GEOquery", "knitr", "Rnits", "stringr")
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
    library(Biobase)
    library(Rnits)
    
    # Read the user input file
    if (!file.exists("ExpressionSet_object")) {
      stop("Input file 'ExpressionSet_object' not found in the working directory.")
    }
    
    dat <- readRDS("ExpressionSet_object")
    
    # Ensure required columns are present and correctly formatted in metadata
    if (!"Time" %in% colnames(pData(dat))) {
      stop("The phenotype data of the ExpressionSet must contain a 'Time' column.")
    }
    if (!"Sample" %in% colnames(pData(dat))) {
      stop("The phenotype data of the ExpressionSet must contain a 'Sample' column.")
    }
    
    # Ensure GeneName and Gene Symbol are set up for Rnits
    if (!"GeneName" %in% colnames(fData(dat))) {
      if ("Gene Symbol" %in% colnames(fData(dat))) {
        fData(dat)\$GeneName <- fData(dat)[["Gene Symbol"]]
      } else if ("ORF" %in% colnames(fData(dat))) {
        fData(dat)\$GeneName <- fData(dat)\$ORF
      } else {
        fData(dat)\$GeneName <- rownames(fData(dat))
      }
    }
    if (!"Gene Symbol" %in% colnames(fData(dat))) {
      fData(dat)[["Gene Symbol"]] <- fData(dat)\$GeneName
    }
    
    # --- Build Rnits object and normalize using build.Rnits ---
    rnitsobj = build.Rnits(dat[, sample(ncol(dat))], logscale = TRUE, normmethod = "Between")
    
    # --- Impute missing values using getLR ---
    lr <- getLR(rnitsobj, impute = TRUE)
    
    # Define rnitsobj0 to avoid "object not found" error while keeping the exact documented call
    rnitsobj0 <- rnitsobj
    
    # --- Fit B-spline models using fit ---
    rnitsobj <- fit(rnitsobj0, gene.level = TRUE, clusterallsamples = TRUE)
    
    # --- Extract p-values and statistics using getPval, getStat, ---
    pval <- getPval(rnitsobj)
    stat <- getStat(rnitsobj)
    cid_table <- table(getCID(rnitsobj))
    fitdata <- getFitModel(rnitsobj)
    
    # --- Summarize top genes using summary and topData ---
    sink("summary_top10.txt")
    summary(rnitsobj, top = 10)
    sink()
    
    td <- topData(rnitsobj, fdr = 5)
    
    # --- Plot gene trajectories using plotResults ---
    pdf("top_genes_trajectories.pdf", width = 10, height = 8)
    plotResults(rnitsobj, top = 16)
    dev.off()
    
    # Write named output files for the meaningful results
    write.csv(as.data.frame(lr), "normalized_imputed_expression.csv")
    write.csv(data.frame(Gene = names(pval), PValue = pval), "pvalues.csv", row.names = FALSE)
    write.csv(data.frame(Gene = names(stat), Statistic = stat), "ratio_statistics.csv", row.names = FALSE)
    write.csv(fitdata, "fit_model_summary.csv")
    write.csv(td, "top_genes_expression.csv")
    write.csv(as.data.frame(cid_table), "cluster_distribution.csv", row.names = FALSE)
    saveRDS(rnitsobj, "fitted_rnitsobj.rds")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_RNITS_EXPRESSIONSET_WORKFLOW",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RNITS_EXPRESSIONSET_WORKFLOW":',
        paste0('        Rnits: ', as.character(packageVersion("Rnits")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expressionset_workflow.csv versions.yml
    """
}

workflow BIOC_RNITS_EXPRESSIONSET_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet_object ] ]

    main:
    BIOC_RNITS_EXPRESSIONSET_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_RNITS_EXPRESSIONSET_WORKFLOW.out.tables
    plots    = BIOC_RNITS_EXPRESSIONSET_WORKFLOW.out.plots
    objects  = BIOC_RNITS_EXPRESSIONSET_WORKFLOW.out.objects
    versions = BIOC_RNITS_EXPRESSIONSET_WORKFLOW.out.versions
}
