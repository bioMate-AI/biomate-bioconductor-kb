#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEP — differential_protein_expression
// Identify differentially expressed proteins from mass spectrometry intensity data using a robust filtering, normalization, imputation, and linear modeling workfl
// Input: proteinGroups.txt, experimental_design.txt
// Container: quay.io/biocontainers/bioconductor-dep:1.32.0--r45hdfd78af_0
// R packages: BiocStyle, DEP, dplyr, ggplot2, purrr, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: DEP, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate unique names for proteins using make_unique
//  * 2. [Visualization & Output] Create a SummarizedExperiment object using make_se
//  * 3. [Core Analysis] Filter out proteins with too many missing values using filter_missval
//  * 4. [Core Analysis] Normalize the data using normalize_vsn
//  * 5. [Core Analysis] Impute missing values using impute
//  * 6. [Core Analysis] Test for differential expression using test_diff
//  * 7. [Input & Preparation] Define significant proteins using add_rejections
//  * 8. [Core Analysis] Extract results table using get_results

nextflow.enable.dsl = 2

process BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION {
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
    .bm_deps <- c("BiocStyle", "DEP", "dplyr", "ggplot2", "purrr", "SummarizedExperiment")
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
        library(DEP)
        
        # Define input file paths
        protein_groups_file <- "proteinGroups.txt"
        experimental_design_file <- "experimental_design.txt"
        
        # Check if input files exist
        if (!file.exists(protein_groups_file)) {
          stop(paste("Error: Input file missing:", protein_groups_file))
        }
        if (!file.exists(experimental_design_file)) {
          stop(paste("Error: Input file missing:", experimental_design_file))
        }
        
        # Read input files
        proteins_tbl <- read.delim(protein_groups_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        experimental_design <- read.delim(experimental_design_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        
        # 1. Generate unique names for proteins
        data_unique <- make_unique(proteins_tbl, "Gene.names", "Protein.IDs", delim = ";")
        
        # Identify the column indices in data_unique that correspond to the labels in experimental_design
        columns <- match(experimental_design\$label, colnames(data_unique))
        if (any(is.na(columns))) {
          stop("Error: Some sample labels in experimental_design do not match column names in proteinGroups.txt")
        }
        
        # 2. Create a SummarizedExperiment object
        se <- make_se(data_unique, columns, experimental_design)
        
        # 3. Filter out proteins with too many missing values
        filt <- filter_missval(se, thr = 0)
        
        # 4. Normalize the data
        norm <- normalize_vsn(filt)
        
        # 5. Impute missing values
        imputed <- impute(norm, fun = "MinProb")
        
        # 6. Test for differential expression
        diff <- test_diff(imputed, type = "all")
        
        # 7. Define significant proteins
        dep <- add_rejections(diff, alpha = 0.05, lfc = 1)
        
        # 8. Extract results table
        results <- get_results(dep)
        
        # Write output files
        write.csv(results, "dep_results.csv", row.names = FALSE)
        saveRDS(dep, "dep_object.rds")
        
        # Generate diagnostic and results plots
        pdf("dep_plots.pdf", width = 10, height = 8)
        tryCatch({
          plot_pca(dep, x = 1, y = 2, n = 100, point_size = 4)
        }, error = function(e) {
          warning("Could not generate PCA plot: ", e\$message)
        })
        
        tryCatch({
          plot_cor(dep, significant = TRUE, lower = 0, upper = 1)
        }, error = function(e) {
          warning("Could not generate correlation plot: ", e\$message)
        })
        dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION":',
        paste0('    DEP: ', as.character(packageVersion('DEP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_protein_expression.csv versions.yml
    """
}

workflow BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ proteinGroups.txt, experimental_design.txt ] ]

    main:
    BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION.out.tables
    plots    = BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION.out.plots
    objects  = BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION.out.objects
    versions = BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION.out.versions
}
