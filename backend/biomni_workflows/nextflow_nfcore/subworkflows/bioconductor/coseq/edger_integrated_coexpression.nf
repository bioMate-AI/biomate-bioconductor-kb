#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: coseq — edger_integrated_coexpression
// Run co-expression analysis on differentially expressed genes identified via edgeR (using either QLF or LRT tests, or multiple contrasts).
// Input: counts, conds
// Container: quay.io/biocontainers/bioconductor-coseq:1.34.0--r45hdfd78af_0
// R packages: coseq, edgeR
// Bioconductor: 3.20 | R: 4.4
// Requires: coseq, edgeR
// Visualizations: plot (ggplot/base)
// QC: TMM normalization, dispersion/size-factor estimation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a DGEList, normalize, estimate dispersions, and fit GLM
//  * 2. [Core Analysis] Perform QLF or LRT test
//  * 3. [Core Analysis] Run coseq on the count matrix, subsetting by the edgeR test results and specifying alpha
//  * 4. [Core Analysis] Alternatively, extract DE indices manually from multiple contrasts and run coseq with pre-computed normalization factors

nextflow.enable.dsl = 2

process BIOC_COSEQ_EDGER_INTEGRATED_COEXPRESSION {
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
    .bm_deps <- c("coseq", "edgeR", "SummarizedExperiment")
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
    library(SummarizedExperiment)
    library(coseq)
    
    # Set seed for reproducibility
    set.seed(12345)
    
    # Helper function to save coseq results
    save_coseq_results <- function(run_obj, prefix) {
      if (!is.null(run_obj)) {
        # Save RDS object
        saveRDS(run_obj, paste0(prefix, "_results.rds"))
        
        # Save cluster assignments
        lbls <- clusters(run_obj)
        write.csv(data.frame(Gene = names(lbls), Cluster = lbls), 
                  file = paste0(prefix, "_clusters.csv"), row.names = FALSE)
        
        # Save conditional probabilities
        prob <- assay(run_obj)
        write.csv(as.data.frame(prob), 
                  file = paste0(prefix, "_probabilities.csv"), row.names = TRUE)
        
        # Save plots to PDF
        pdf(paste0(prefix, "_plots.pdf"))
        p_box <- try(plot(run_obj, graphs = "boxplots"), silent = TRUE)
        if (!inherits(p_box, "try-error")) {
          if (is.list(p_box) && "boxplots" %in% names(p_box)) {
            print(p_box\$boxplots)
          } else {
            print(p_box)
          }
        }
        p_prof <- try(plot(run_obj, graphs = "profiles"), silent = TRUE)
        if (!inherits(p_prof, "try-error")) {
          if (is.list(p_prof) && "profiles" %in% names(p_prof)) {
            print(p_prof\$profiles)
          } else {
            print(p_prof)
          }
        }
        dev.off()
      }
    }
    
    # ----------------------------------------------------------------------
    # 1. Read User Input Files
    # ----------------------------------------------------------------------
    if (file.exists("counts.csv")) {
      counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("counts.tsv")) {
      counts <- read.delim("counts.tsv", row.names = 1, check.names = FALSE)
    } else if (file.exists("counts.txt")) {
      counts <- read.table("counts.txt", header = TRUE, row.names = 1, check.names = FALSE)
    } else {
      stop("Counts file (counts.csv, counts.tsv, or counts.txt) not found in the working directory!")
    }
    counts <- as.matrix(counts)
    
    if (file.exists("conds.txt")) {
      conds <- readLines("conds.txt")
    } else if (file.exists("conds.csv")) {
      conds_df <- read.csv("conds.csv", header = FALSE)
      conds <- as.character(conds_df[[1]])
    } else {
      stop("Conditions file (conds.txt or conds.csv) not found in the working directory!")
    }
    
    # ----------------------------------------------------------------------
    # 2. Run edgeR Differential Expression Analysis (QLF and LRT)
    # ----------------------------------------------------------------------
    y <- DGEList(counts=counts, group=factor(conds))
    y <- calcNormFactors(y)
    design <- model.matrix(~conds)
    y <- estimateDisp(y, design)
    
    # edgeR: QLF test
    fit <- glmQLFit(y, design)
    qlf <- glmQLFTest(fit, coef=2)
    
    # edgeR: LRT test
    fit <- glmFit(y,design)
    lrt <- glmLRT(fit,coef=2)
    
    # ----------------------------------------------------------------------
    # 3. Run coseq on LRT and QLF Subsets
    # ----------------------------------------------------------------------
    # Run coseq using LRT subset
    run <- coseq(counts, K=2:15, subset=lrt, alpha=0.1)
    save_coseq_results(run, "coseq_lrt")
    
    # Run coseq using QLF subset
    run <- coseq(counts, K=2:15, subset=qlf, alpha=0.1)
    save_coseq_results(run, "coseq_qlf")
    
    # ----------------------------------------------------------------------
    # 4. Multi-contrast edgeR and coseq Analysis (Optional based on design)
    # ----------------------------------------------------------------------
    if (ncol(design) >= 3) {
      y <- DGEList(counts=counts)
      y <- calcNormFactors(y)
      y <- estimateDisp(y, design)
      fit <- glmQLFit(y, design)
      qlf_1 <- glmQLFTest(fit, coef=2)
      qlf_2 <- glmQLFTest(fit, coef=3)
      de_indices <- c(unique(
          which(topTags(qlf_1, sort.by = "none", n=Inf)\$table\$FDR < 0.05),
          which(topTags(qlf_2, sort.by = "none", n=Inf)\$table\$FDR < 0.05)
      ))
      run <- coseq(counts, K=2:25, 
                   normFactors = y\$samples\$norm.factors,
                   subset = de_indices)
      save_coseq_results(run, "coseq_multicontrast")
    } else {
      message("Skipping multi-contrast stage because design matrix has fewer than 3 coefficients (requires >= 3 conditions).")
    }
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

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_COSEQ_EDGER_INTEGRATED_COEXPRESSION",
      domain  = "bioconductor",
      declared_qc_steps = c("TMM normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_COSEQ_EDGER_INTEGRATED_COEXPRESSION":',
        paste0('    coseq: ', as.character(packageVersion('coseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_edger_integrated_coexpression.csv versions.yml
    """
}

workflow BIOC_COSEQ_EDGER_INTEGRATED_COEXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts, conds ] ]

    main:
    BIOC_COSEQ_EDGER_INTEGRATED_COEXPRESSION(ch_input)

    emit:
    tables   = BIOC_COSEQ_EDGER_INTEGRATED_COEXPRESSION.out.tables
    plots    = BIOC_COSEQ_EDGER_INTEGRATED_COEXPRESSION.out.plots
    objects  = BIOC_COSEQ_EDGER_INTEGRATED_COEXPRESSION.out.objects
    versions = BIOC_COSEQ_EDGER_INTEGRATED_COEXPRESSION.out.versions
}
