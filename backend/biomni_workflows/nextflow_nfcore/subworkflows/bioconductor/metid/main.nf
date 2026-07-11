#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetID — lc_ms_metabolite_id_scoring
// Score and prioritize putative metabolite identifications from LC-MS data using a network-based probabilistic framework.
// Input: metabolomics_data.csv
// Container: quay.io/biocontainers/bioconductor-metid:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetID
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the MetID package and the input dataset
//  * 2. [Core Analysis] Format the column names of the dataset to meet the package's strict requirements
//  * 3. [Input & Preparation] Run get_scores_for_LC_MS to build the network, perform random sampling, and calculate identification scores

nextflow.enable.dsl = 2

process BIOC_METID_LC_MS_METABOLITE_ID_SCORING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("MetID")
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
    
    # Load MetID package
    library(MetID)
    
    # Read the user input file
    input_file <- "metabolomics_data.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    raw_data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Helper to find column by name (case-insensitive, ignoring punctuation)
    find_col <- function(names_list, patterns) {
      for (pat in patterns) {
        idx <- grep(pat, names_list, ignore.case = TRUE)
        if (length(idx) > 0) return(idx[1])
      }
      return(NULL)
    }
    
    q_idx <- find_col(colnames(raw_data), c("query_m.z", "query.mass", "query", "m.z", "mz"))
    name_idx <- find_col(colnames(raw_data), c("name"))
    form_idx <- find_col(colnames(raw_data), c("formula"))
    e_idx <- find_col(colnames(raw_data), c("exact_m.z", "exact.mass", "exact"))
    pub_idx <- find_col(colnames(raw_data), c("pubchem_cid", "pubchem", "cid"))
    kegg_idx <- find_col(colnames(raw_data), c("kegg_id", "kegg"))
    metid_idx <- find_col(colnames(raw_data), c("metid", "peak", "id"))
    
    # Construct demo1 with exactly 6 columns to match the documented code's renaming step
    demo1 <- data.frame(
      Query.Mass = if (!is.null(q_idx)) as.numeric(raw_data[[q_idx]]) else rep(NA, nrow(raw_data)),
      Name = if (!is.null(name_idx)) as.character(raw_data[[name_idx]]) else rep("", nrow(raw_data)),
      Formula = if (!is.null(form_idx)) as.character(raw_data[[form_idx]]) else rep("", nrow(raw_data)),
      Exact.Mass = if (!is.null(e_idx)) as.numeric(raw_data[[e_idx]]) else rep(NA, nrow(raw_data)),
      PubChem.CID = if (!is.null(pub_idx)) as.character(raw_data[[pub_idx]]) else rep("-", nrow(raw_data)),
      KEGG.ID = if (!is.null(kegg_idx)) as.character(raw_data[[kegg_idx]]) else rep("-", nrow(raw_data)),
      stringsAsFactors = FALSE
    )
    
    # Handle missing values for PubChem and KEGG IDs to match the na='-' parameter
    demo1\$PubChem.CID[is.na(demo1\$PubChem.CID) | demo1\$PubChem.CID == "" | demo1\$PubChem.CID == "NA"] <- "-"
    demo1\$KEGG.ID[is.na(demo1\$KEGG.ID) | demo1\$KEGG.ID == "" | demo1\$KEGG.ID == "NA"] <- "-"
    
    # Format the column names of the dataset to meet the package's strict requirements
    colnames(demo1) <- c('query_m.z','name','formula','exact_m.z','pubchem_cid','kegg_id')
    
    # If peak IDs (metid) were provided, add them to the formatted data frame
    if (!is.null(metid_idx)) {
      demo1\$metid <- as.character(raw_data[[metid_idx]])
    }
    
    # Run get_scores_for_LC_MS to build the network, perform random sampling, and calculate identification scores
    out <- get_scores_for_LC_MS(demo1, type = 'data.frame', na='-', mode='POS')
    
    # Print head of the output to console
    head(out)
    
    # Save the results to output files
    write.csv(out, "metabolite_scores.csv", row.names = FALSE)
    saveRDS(out, "metabolite_scores.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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
      process = "BIOC_METID_LC_MS_METABOLITE_ID_SCORING",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_METID_LC_MS_METABOLITE_ID_SCORING":',
        paste0('    MetID: ', as.character(packageVersion('MetID')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lc_ms_metabolite_id_scoring.csv versions.yml
    """
}

workflow BIOC_METID_LC_MS_METABOLITE_ID_SCORING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ metabolomics_data.csv ] ]

    main:
    BIOC_METID_LC_MS_METABOLITE_ID_SCORING(ch_input)

    emit:
    tables   = BIOC_METID_LC_MS_METABOLITE_ID_SCORING.out.tables
    plots    = BIOC_METID_LC_MS_METABOLITE_ID_SCORING.out.plots
    objects  = BIOC_METID_LC_MS_METABOLITE_ID_SCORING.out.objects
    versions = BIOC_METID_LC_MS_METABOLITE_ID_SCORING.out.versions
}
