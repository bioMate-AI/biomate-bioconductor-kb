#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BADER — bayesian_differential_expression
// Perform Bayesian differential expression analysis on RNA-seq count data to estimate posterior probabilities of differential expression and log fold changes, fol
// Input: pasilla_gene_counts.tsv
// Container: quay.io/biocontainers/bioconductor-bader:1.48.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BADER
// Visualizations: plot (ggplot/base)
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the count data and define the experimental design factor
//  * 2. [Core Analysis] Filter out genes with zero counts across all samples and subset the dataset
//  * 3. [Core Analysis] Run the BADER MCMC sampler to estimate posterior probabilities
//  * 4. [Core Analysis] Extract posterior probabilities of differential expression and identify top genes
//  * 5. [Core Analysis] Run the BADER MCMC sampler in full mode to obtain the posterior distribution of log fold changes
//  * 6. [Core Analysis] Perform gene set enrichment analysis using the posterior distribution of log fold changes

nextflow.enable.dsl = 2

process BIOC_BADER_BAYESIAN_DIFFERENTIAL_EXPRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("BADER")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
            
    # 1. Load the count data and define the experimental design factor
    library(BADER)
    
    # Read the user input file from the working directory
    datafile <- "pasilla_gene_counts.tsv"
    pasillaCountTable <- read.table(datafile, header=TRUE, row.names=1, sep="\t")
    
    # 2. Filter out genes with zero counts across all samples
    genetable <- pasillaCountTable
    genetable <- genetable[rowSums(genetable) > 0, ]
    design <- factor(ifelse(seq_len(ncol(genetable)) <= ncol(genetable) / 2, "A", "B"))
    
    # 3. Run the BADER MCMC sampler to estimate posterior probabilities
    set.seed(21)
    results_minimal <- BADER(genetable, design, burn=1e3, reps=1e3, printEvery=1e3)
    
    # 4. Extract posterior probabilities of differential expression and identify top genes
    names(results_minimal)
    top_genes <- rownames(genetable)[order(results_minimal\$diffProb, decreasing=TRUE)[1:10]]
    
    # Save the top genes and their posterior probabilities to a CSV file
    diff_expr_summary <- data.frame(
      GeneID = rownames(genetable),
      DiffProb = results_minimal\$diffProb,
      LogFoldChange = results_minimal\$logFoldChange
    )
    diff_expr_summary <- diff_expr_summary[order(diff_expr_summary\$DiffProb, decreasing=TRUE), ]
    write.csv(diff_expr_summary, "bader_differential_expression_results.csv", row.names=FALSE)
    
    # 5. Run the BADER MCMC sampler in full mode to obtain the posterior distribution of log fold changes
    set.seed(21)
    results <- BADER(genetable, design, mode="full", burn=1e3, reps=3e3, printEvery=1e3)
    
    # Save the full MCMC results object to an RDS file
    saveRDS(results, "bader_full_mcmc_results.rds")
    
    # 6. Perform gene set enrichment analysis using the posterior distribution of log fold changes
    S <- c(1, 2, 3, 51, 52, 53)
    T_set <- c(54, 55, 56)
    
    f <- function(sample, set) {
      mean(sample[set] != 0) > mean(sample[-set] != 0)
    }
    
    gse_S <- mean(apply(results\$logFoldChangeDist, 1, f, set=S))
    gse_T <- mean(apply(results\$logFoldChangeDist, 1, f, set=T_set))
    
    # Save gene set enrichment results to a text file
    gse_results <- data.frame(
      GeneSet = c("S", "T"),
      EnrichmentProbability = c(gse_S, gse_T)
    )
    write.csv(gse_results, "gene_set_enrichment_results.csv", row.names=FALSE)
    
    # 7. Generate diagnostic plots of the posterior distributions for selected genes
    pdf("posterior_log_fold_change_plots.pdf", width=10, height=5)
    par(mfrow=c(1, 2))
    
    # Gene 18
    temp18 <- hist(results\$logFoldChangeDist[, 18], plot=FALSE)
    temp18\$density <- temp18\$density / sum(temp18\$density)
    plot(temp18, freq=FALSE, ylab="probability", xlab="log fold change", main="gene no. 18")
    abline(v=results\$logFoldChange[18], col="#377EB8", lwd=2)
    
    # Gene 142
    temp142 <- hist(results\$logFoldChangeDist[, 142], plot=FALSE)
    temp142\$density <- temp142\$density / sum(temp142\$density)
    plot(temp142, freq=FALSE, ylab="probability", xlab="log fold change", main="gene no. 142")
    abline(v=results\$logFoldChange[142], col="#377EB8", lwd=2)
    
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_BADER_BAYESIAN_DIFFERENTIAL_EXPRESSION",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BADER_BAYESIAN_DIFFERENTIAL_EXPRESSION":',
        paste0('    BADER: ', as.character(packageVersion('BADER')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bayesian_differential_expression.csv versions.yml
    """
}

workflow BIOC_BADER_BAYESIAN_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pasilla_gene_counts.tsv ] ]

    main:
    BIOC_BADER_BAYESIAN_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_BADER_BAYESIAN_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_BADER_BAYESIAN_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_BADER_BAYESIAN_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_BADER_BAYESIAN_DIFFERENTIAL_EXPRESSION.out.versions
}
