#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSAR — rnaseq_gsa
// Perform self-contained gene set analysis on RNA-seq count data, handling normalization and filtering of zero-variance genes.
// Input: PickrellDataSet, genes.length, group.label.pickrell, XYgenes
// Container: quay.io/biocontainers/bioconductor-gsar:1.44.0--r45hdfd78af_0
// R packages: GSAR, edgeR
// Bioconductor: 3.20 | R: 4.4
// Requires: GSAR, edgeR
// Visualizations: pathway diagram
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read user input files from the working directory
//  * 2. [Core Analysis] Execute the documented workflow steps
//  * 3. [Core Analysis] Write named output files for the results

nextflow.enable.dsl = 2

process BIOC_GSAR_RNASEQ_GSA {
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
    .bm_deps <- c("GSAR", "edgeR")
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
        library(edgeR)
        library(GSAR)
        
        # Helper function to load matrix inputs robustly
        load_matrix <- function(name) {
          for (ext in c(".rds", "", ".csv", ".tsv", ".txt")) {
            file <- paste0(name, ext)
            if (file.exists(file)) {
              if (grepl("\\\\.rds\$", file, ignore.case = TRUE)) {
                return(as.matrix(readRDS(file)))
              } else {
                tryCatch({
                  return(as.matrix(read.csv(file, row.names = 1, check.names = FALSE)))
                }, error = function(e) {
                  return(as.matrix(read.csv(file, header = TRUE, check.names = FALSE)))
                })
              }
            }
          }
          stop(paste("Matrix file not found:", name))
        }
        
        # Helper function to load vector inputs robustly
        load_vector <- function(name, mode = "numeric") {
          for (ext in c(".rds", "", ".csv", ".tsv", ".txt")) {
            file <- paste0(name, ext)
            if (file.exists(file)) {
              if (grepl("\\\\.rds\$", file, ignore.case = TRUE)) {
                val <- readRDS(file)
                if (mode == "numeric") return(as.numeric(val))
                return(as.character(val))
              } else {
                tryCatch({
                  df <- read.csv(file, header = FALSE, stringsAsFactors = FALSE)
                  val <- df[[1]]
                  if (mode == "numeric") {
                    if (is.na(as.numeric(val[1]))) {
                      df <- read.csv(file, header = TRUE, stringsAsFactors = FALSE)
                      val <- df[[1]]
                    }
                    return(as.numeric(val))
                  } else {
                    return(as.character(val))
                  }
                }, error = function(e) {
                  lines <- readLines(file)
                  if (mode == "numeric") return(as.numeric(lines))
                  return(as.character(lines))
                })
              }
            }
          }
          stop(paste("Vector file not found:", name))
        }
        
        # --- Read user input files from the working directory ---
        PickrellDataSet      <- load_matrix("PickrellDataSet")
        genes.length         <- load_vector("genes.length", "numeric")
        group.label.pickrell <- load_vector("group.label.pickrell", "numeric")
        XYgenes              <- load_vector("XYgenes", "character")
        
        # Reconstruct the 'gender' variable to ensure the documented code runs seamlessly
        # group.label.pickrell is expected to be 1 for female and 2 for male
        gender <- ifelse(group.label.pickrell == 2, "male", "female")
        
        # --- Execute the documented workflow steps ---
        cpm.matrix <- cpm(PickrellDataSet)
        cpm.means <- rowMeans(cpm.matrix)
        cpm.filter <- which(cpm.means > 0.1)
        PickrellDataSet <- PickrellDataSet[cpm.filter,]
        genes.length <- genes.length[cpm.filter]
        rpkm.set <- rpkm(PickrellDataSet, genes.length)
        rpkm.set <- log2(1 + rpkm.set)
        
        # Filter target pathway genes to only those present in the normalized dataset
        XYgenes <- XYgenes[XYgenes %in% rownames(rpkm.set)]
        XYpathway <- rpkm.set[XYgenes,]
        
        group.label.pickrell <- (gender == "male") + 1
        
        # Run statistical tests on the initial pathway matrix
        WW_pvalue <- WWtest(XYpathway, group.label.pickrell)
        KS_pvalue <- KStest(XYpathway, group.label.pickrell)
        
        # Filter out genes with zero or tiny standard deviation (< 1e-3) in either group
        tiny.sd.XY.female <- which(apply(XYpathway[, group.label.pickrell == 1], 1, "sd") < 1e-3)
        tiny.sd.XY.male <- which(apply(XYpathway[, group.label.pickrell == 2], 1, "sd") < 1e-3)
        tiny.sd.XY.remove <- unique(c(tiny.sd.XY.male, tiny.sd.XY.female))
        if(length(tiny.sd.XY.remove) > 0) XYpathway <- XYpathway[-tiny.sd.XY.remove,]
        
        # Run statistical tests on the filtered pathway matrix
        WW_pvalue_filtered <- WWtest(XYpathway, group.label.pickrell)
        KS_pvalue_filtered <- KStest(XYpathway, group.label.pickrell)
        
        # --- Write named output files for the results ---
        # Save the p-values to a CSV table
        results_df <- data.frame(
          Analysis_Stage = c("Pre-filtering", "Pre-filtering", "Post-filtering", "Post-filtering"),
          Test = c("Wald-Wolfowitz (WWtest)", "Kolmogorov-Smirnov (KStest)", "Wald-Wolfowitz (WWtest)", "Kolmogorov-Smirnov (KStest)"),
          P_Value = c(WW_pvalue, KS_pvalue, WW_pvalue_filtered, KS_pvalue_filtered)
        )
        write.csv(results_df, "gsa_results.csv", row.names = FALSE)
        
        # Save the normalized, filtered pathway expression matrix
        write.csv(as.data.frame(XYpathway), "XYpathway_normalized_filtered_expression.csv")
        saveRDS(XYpathway, "XYpathway_normalized_filtered_expression.rds")
        
        # Generate and save the Minimum Spanning Tree (MST2) plots to a PDF
        tryCatch({
          pdf("XYpathway_MST2_plots.pdf", width = 12, height = 7)
          plotMST2.pathway(
            object = XYpathway,
            group = group.label.pickrell,
            name = "XYpathway",
            legend.size = 1.2,
            cor.method = "pearson"
          )
          dev.off()
        }, error = function(e) {
          warning("Could not generate MST2 plot: ", e\$message)
        })
        
        cat("Pipeline completed successfully. Outputs written to 'gsa_results.csv', 'XYpathway_normalized_filtered_expression.csv', and 'XYpathway_MST2_plots.pdf'.\n")
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_GSAR_RNASEQ_GSA",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GSAR_RNASEQ_GSA":',
        paste0('    GSAR: ', as.character(packageVersion('GSAR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseq_gsa.csv versions.yml
    """
}

workflow BIOC_GSAR_RNASEQ_GSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PickrellDataSet, genes.length, group.label.pickrell, XYgenes ] ]

    main:
    BIOC_GSAR_RNASEQ_GSA(ch_input)

    emit:
    tables   = BIOC_GSAR_RNASEQ_GSA.out.tables
    plots    = BIOC_GSAR_RNASEQ_GSA.out.plots
    objects  = BIOC_GSAR_RNASEQ_GSA.out.objects
    versions = BIOC_GSAR_RNASEQ_GSA.out.versions
}
