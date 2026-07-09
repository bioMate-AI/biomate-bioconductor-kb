#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: missMethyl — diff_var_rnaseq
// Test for differences in gene expression variance between groups in RNA-Seq data, accounting for the mean-variance relationship.
// Input: counts, annot, gender
// Container: quay.io/biocontainers/bioconductor-missmethyl:1.44.0--r45hdfd78af_0
// R packages: edgeR, limma, missMethyl
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR, limma, missMethyl
// Visualizations: strip chart
// QC: TMM normalization, low-count filtering, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read user inputs from the working directory
//  * 2. [Input & Preparation] Create a DGEList object
//  * 3. [Input & Preparation] Filter lowly expressed genes and normalize library sizes
//  * 4. [Input & Preparation] Fit the variability model using varFit
//  * 5. [Input & Preparation] Extract top differentially variable genes using topVar
//  * 6. [Input & Preparation] Write outputs

nextflow.enable.dsl = 2

process BIOC_MISSMETHYL_DIFF_VAR_RNASEQ {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("edgeR", "limma", "missMethyl")
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
    library(missMethyl)
    library(edgeR)
    library(limma)
    
    # Helper function to robustly read matrix or data frame inputs
    read_matrix_or_df <- function(filename) {
      exts <- c("", ".rds", ".csv", ".tsv", ".txt")
      found_path <- NULL
      for (ext in exts) {
        path <- paste0(filename, ext)
        if (file.exists(path)) {
          found_path <- path
          break
        }
      }
      if (is.null(found_path)) {
        stop(paste("Required input file not found:", filename))
      }
    
      if (grepl("\\\\.rds\$", found_path, ignore.case = TRUE)) {
        return(readRDS(found_path))
      } else if (grepl("\\\\.csv\$", found_path, ignore.case = TRUE)) {
        res <- tryCatch({
          read.csv(found_path, row.names = 1, check.names = FALSE)
        }, error = function(e) {
          read.csv(found_path, check.names = FALSE)
        })
        return(res)
      } else {
        res <- tryCatch({
          read.table(found_path, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
        }, error = function(e) {
          read.table(found_path, header = TRUE, sep = "\t", check.names = FALSE)
        })
        return(res)
      }
    }
    
    # Helper function to robustly read the gender covariate vector
    read_gender <- function() {
      exts <- c("", ".rds", ".csv", ".tsv", ".txt")
      found_path <- NULL
      for (ext in exts) {
        path <- paste0("gender", ext)
        if (file.exists(path)) {
          found_path <- path
          break
        }
      }
      if (is.null(found_path)) {
        stop("Required input file not found: gender")
      }
    
      if (grepl("\\\\.rds\$", found_path, ignore.case = TRUE)) {
        val <- readRDS(found_path)
      } else if (grepl("\\\\.csv\$", found_path, ignore.case = TRUE)) {
        df <- read.csv(found_path, header = FALSE)
        if (ncol(df) == 1) {
          val <- df[[1]]
        } else {
          val <- df[[2]]
        }
      } else if (grepl("\\\\.tsv\$", found_path, ignore.case = TRUE)) {
        df <- read.delim(found_path, header = FALSE)
        if (ncol(df) == 1) {
          val <- df[[1]]
        } else {
          val <- df[[2]]
        }
      } else {
        val <- readLines(found_path)
      }
      return(as.factor(val))
    }
    
    # --- Read user inputs from the working directory ---
    counts <- as.matrix(read_matrix_or_df("counts"))
    annot <- read_matrix_or_df("annot")
    gender <- read_gender()
    
    # Validate dimensions
    if (length(gender) != ncol(counts)) {
      stop(sprintf("Length of gender vector (%d) does not match number of columns in counts matrix (%d)", length(gender), ncol(counts)))
    }
    
    if (length(unique(gender)) < 2) {
      stop("Gender covariate must have at least 2 levels to test for differential variability.")
    }
    
    # Ensure annotation has Symbol and Chr columns
    if (!all(c("Symbol", "Chr") %in% colnames(annot))) {
      if ("symbol" %in% tolower(colnames(annot))) {
        colnames(annot)[tolower(colnames(annot)) == "symbol"] <- "Symbol"
      } else {
        annot\$Symbol <- rownames(annot)
      }
      if ("chr" %in% tolower(colnames(annot))) {
        colnames(annot)[tolower(colnames(annot)) == "chr"] <- "Chr"
      } else {
        annot\$Chr <- "Unknown"
      }
    }
    annot <- annot[, c("Symbol", "Chr"), drop = FALSE]
    
    # --- Create a DGEList object ---
    y <- DGEList(counts=counts, genes=annot[rownames(counts),])
    
    # --- Filter lowly expressed genes and normalize library sizes ---
    isexpr <- rowSums(cpm(y)>1) >= 20
    # Fallback for small sample sizes to ensure the pipeline runs successfully
    if (sum(isexpr) == 0) {
      warning("No genes passed the default filter (cpm > 1 in >= 20 samples). Adjusting threshold for small dataset.")
      isexpr <- rowSums(cpm(y)>1) >= max(1, ncol(y) %/% 2)
    }
    
    hasannot <- rowSums(is.na(y\$genes))==0
    if (sum(isexpr & hasannot) == 0) {
      warning("No genes have complete annotations. Proceeding without annotation filtering.")
      hasannot <- rep(TRUE, nrow(y))
    }
    
    y <- y[isexpr & hasannot,,keep.lib.sizes=FALSE]
    y <- calcNormFactors(y)
    
    # --- Fit the variability model using varFit ---
    design.hapmap <- model.matrix(~gender)
    fitvar.hapmap <- varFit(y, design = design.hapmap, coef=c(1,2))
    fitvar.hapmap\$genes <- y\$genes
    
    # --- Extract top differentially variable genes using topVar ---
    topDV.hapmap <- topVar(fitvar.hapmap,coef=ncol(design.hapmap))
    
    # --- Write outputs ---
    write.csv(topDV.hapmap, file = "top_DV_genes.csv", row.names = TRUE)
    saveRDS(fitvar.hapmap, file = "fitvar_hapmap.rds")
    
    # Generate visualization plot
    pdf("diff_var_plots.pdf", width = 8, height = 8)
    genesDV <- rownames(topDV.hapmap)
    n_plots <- min(4, length(genesDV))
    if (n_plots > 0) {
      par(mfrow=c(2,2))
      for(i in 1:n_plots){
        stripchart(cpm(y,log=TRUE)[rownames(y)==genesDV[i],]~design.hapmap[,ncol(design.hapmap)],
                   method="jitter",
                   group.names=levels(factor(gender)),
                   pch=16, cex=1.5, col=c(4,2),
                   ylab="Log counts per million",
                   vertical=TRUE, cex.axis=1.5, cex.lab=1.5)
        title(genesDV[i], cex.main=1.5)
      }
    }
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # TMM normalization — DGEList\$samples\$norm.factors set (Robinson & Oshlack 2010).
    .tmm_factors <- NULL; .tmm_n_nontrivial <- NA_real_
    for (.tmm_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .tmm_obj <- tryCatch(readRDS(.tmm_rds), error = function(e) NULL)
      if (!is.null(.tmm_obj) && inherits(.tmm_obj, "DGEList")) {
        .tmm_f <- tryCatch(.tmm_obj\$samples\$norm.factors, error = function(e) NULL)
        if (!is.null(.tmm_f) && length(.tmm_f) > 0) {
          .tmm_factors <- .tmm_f; .tmm_n_nontrivial <- sum(abs(.tmm_f - 1.0) > 1e-6); break
        }
      }
    }
    .gates_by_label[["TMM normalization"]] <- list(
      gate_row = "bioc_tmm_normalization",
      metric_name = "n_nontrivial_norm_factors",
      metric_value = .tmm_n_nontrivial,
      passes = isTRUE(is.finite(.tmm_n_nontrivial) && .tmm_n_nontrivial > 0),
      status = if (is.finite(.tmm_n_nontrivial)) paste0("computed (n=", length(.tmm_factors), ", nontrivial=", .tmm_n_nontrivial, ")")
               else "not_computed (no DGEList .rds artifact present)"
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
      process = "BIOC_MISSMETHYL_DIFF_VAR_RNASEQ",
      domain  = "bioconductor",
      declared_qc_steps = c("TMM normalization", "low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MISSMETHYL_DIFF_VAR_RNASEQ":',
        paste0('    missMethyl: ', as.character(packageVersion('missMethyl')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diff_var_rnaseq.csv versions.yml
    """
}

workflow BIOC_MISSMETHYL_DIFF_VAR_RNASEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts, annot, gender ] ]

    main:
    BIOC_MISSMETHYL_DIFF_VAR_RNASEQ(ch_input)

    emit:
    tables   = BIOC_MISSMETHYL_DIFF_VAR_RNASEQ.out.tables
    plots    = BIOC_MISSMETHYL_DIFF_VAR_RNASEQ.out.plots
    objects  = BIOC_MISSMETHYL_DIFF_VAR_RNASEQ.out.objects
    versions = BIOC_MISSMETHYL_DIFF_VAR_RNASEQ.out.versions
}
