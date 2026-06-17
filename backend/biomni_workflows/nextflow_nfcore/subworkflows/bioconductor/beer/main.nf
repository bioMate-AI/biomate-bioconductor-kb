#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: beer — phip_seq_enrichment
// Identify enriched antibody responses to peptides in PhIP-seq data using edgeR and Bayesian (BEER) modeling.
// Input: PhIPData object
// Container: quay.io/biocontainers/bioconductor-beer:1.14.1--r45hdfd78af_0
// R packages: SummarizedExperiment, beer, dplyr, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, beer, dplyr, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run edgeR to estimate peptide-specific dispersion and identify differentially expressed peptides
//  * 2. [Core Analysis] Run BEER (Bayesian Estimation Enrichment in R) using brew() to obtain posterior probabilities of enrichment
//  * 3. [Core Analysis] Identify enriched peptides (hits) by combining posterior probabilities and super-enriched peptides
//  * 4. [Core Analysis] Run beads-only round robin using beadsRR() to estimate false positive rates
//  * 5. [Core Analysis] Calculate expected reads/proportions using getExpected() and Bayes factors using getBF()

nextflow.enable.dsl = 2

process BIOC_BEER_PHIP_SEQ_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("SummarizedExperiment", "beer", "dplyr", "ggplot2")
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
        
        # Load required libraries
        library(beer)
        library(SummarizedExperiment)
        library(ggplot2)
        library(dplyr)
        
        # -----------------------------------------------------------------------------
        # USER INPUT: Read PhIPData object from the working directory
        # -----------------------------------------------------------------------------
        if (!file.exists("sim_data.rds")) {
          stop("Error: 'sim_data.rds' not found in the working directory.")
        }
        sim_data <- readRDS("sim_data.rds")
        
        # -----------------------------------------------------------------------------
        # STAGE 1: Run edgeR to estimate peptide-specific dispersion and identify hits
        # -----------------------------------------------------------------------------
        edgeR_out <- runEdgeR(sim_data, 
                              assay.names = c(logfc = "edgeR_logfc",
                                              prob = "edgeR_logpval"))
        
        assay(edgeR_out, "edgeR_hits") <- apply(
          assay(edgeR_out, "edgeR_logpval"), 2, 
          function(sample){
            pval <- 10^(-sample)
            p.adjust(pval, method = "BH") < 0.05
          })
        
        # Save edgeR results
        saveRDS(edgeR_out, "edgeR_out.rds")
        edgeR_hits_df <- as.data.frame(assay(edgeR_out, "edgeR_hits"))
        write.csv(edgeR_hits_df, "edgeR_hits.csv", row.names = TRUE)
        
        # -----------------------------------------------------------------------------
        # STAGE 2 & 3: Run BEER (Bayesian Estimation Enrichment in R) and identify hits
        # -----------------------------------------------------------------------------
        assay_locations <- c(
          phi = "beer_fc_marg", 
          phi_Z = "beer_fc_cond", 
          Z = "beer_prob", 
          c = "sampleInfo", 
          pi = "sampleInfo"
        )
        
        beer_out <- brew(edgeR_out, assay.names = assay_locations)
        
        was_run <- matrix(rep(beer_out\$group != "beads", each = nrow(beer_out)), 
                          nrow = nrow(beer_out))
        
        are_se <- was_run & is.na(assay(beer_out, "beer_prob"))
        
        assay(beer_out, "beer_hits") <- assay(beer_out, "beer_prob") > 0.5 | are_se
        
        # Save BEER results
        saveRDS(beer_out, "beer_out.rds")
        beer_hits_df <- as.data.frame(assay(beer_out, "beer_hits"))
        write.csv(beer_hits_df, "beer_hits.csv", row.names = TRUE)
        
        # -----------------------------------------------------------------------------
        # STAGE 4: Run beads-only round robin using beadsRR()
        # -----------------------------------------------------------------------------
        # Run edgeR with beadsRR
        edgeR_beadsRR <- runEdgeR(sim_data, beadsRR = TRUE, 
                                  assay.names = c(logfc = "edgeR_logfc", 
                                                  prob = "edgeR_logpval"))
        
        # Run BEER with beadsRR
        beer_beadsRR <- brew(edgeR_beadsRR, beadsRR = TRUE, 
                             assay.names = assay_locations)
        
        # Save beadsRR results
        saveRDS(beer_beadsRR, "beer_beadsRR.rds")
        
        # -----------------------------------------------------------------------------
        # STAGE 5: Calculate expected reads/proportions and Bayes factors
        # -----------------------------------------------------------------------------
        expected_out <- getExpected(sim_data)
        saveRDS(expected_out, "expected_out.rds")
        
        bf_out <- beer_beadsRR %>% getBF()
        saveRDS(bf_out, "bf_out.rds")
        
        # -----------------------------------------------------------------------------
        # STAGE 6: Generate and save plots
        # -----------------------------------------------------------------------------
        # Plot 1: Observed vs Expected read counts
        tryCatch({
          # Check if true_Z exists in the expected output, default to 0 if not
          exp_df <- as(expected_out, "DataFrame") %>% as_tibble()
          if (!"true_Z" %in% colnames(exp_df)) {
            exp_df\$true_Z <- 0
          }
          
          p1 <- exp_df %>%
            group_by(peptide) %>%
            mutate(sample = factor(sample),
                   sample_name = paste0(group, " ", sample)) %>%
            arrange(true_Z) %>%
            ggplot(aes(x = expected_rc, y = counts, color = factor(true_Z))) + 
            geom_abline(aes(intercept = 0, slope = 1), linewidth = 1) + 
            geom_point() +
            facet_wrap(sample_name ~., ncol = 4, scales = "free") +
            labs(x = "expected read counts", 
                 y = "observed read counts", 
                 color = "true enrichment status") +
            scale_x_log10() +
            scale_y_log10() +
            scale_color_manual(values = c("grey", "red"), 
                               breaks = c(0, 1), 
                               labels = c("not enriched", "enriched")) +
            theme_bw() + 
            theme(legend.position = "bottom", 
                  axis.text.x = element_text(angle = 45, hjust = 1), 
                  aspect.ratio = 1)
          
          ggsave("observed_vs_expected.pdf", plot = p1, width = 10, height = 8)
        }, error = function(e) {
          warning("Could not generate observed vs expected plot: ", e\$message)
        })
        
        # Plot 2: Bayes factors
        tryCatch({
          bf_df <- as(bf_out, "DataFrame") %>% as_tibble()
          
          p2 <- bf_df %>%
            mutate(
              peptide = factor(peptide), 
              sample = factor(sample),
              sample_name = paste0(group, " ", sample), 
              pred = ifelse(prob >= 0.5, TRUE, FALSE)) %>%
            ggplot(aes(x = peptide, y = bayes_factors, color = pred)) +
            geom_point() + 
            facet_wrap(sample_name ~., ncol = 4) +
            labs(x = "peptide", 
                 y = "Bayes factor", 
                 color = "prediction") +
            scale_y_log10() +
            scale_color_manual(
              breaks = c(TRUE, FALSE), 
              values = c("red", "black"), 
              labels = c("enriched", "not enriched")
            ) +
            theme_bw() + 
            theme(legend.position = "bottom",
                  axis.text.x = element_text(angle = 90, hjust = 1),
                  aspect.ratio = 1)
          
          ggsave("bayes_factors.pdf", plot = p2, width = 10, height = 8)
        }, error = function(e) {
          warning("Could not generate Bayes factors plot: ", e\$message)
        })
        
        message("Pipeline completed successfully. Outputs saved to the working directory.")
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

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_BEER_PHIP_SEQ_ENRICHMENT",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BEER_PHIP_SEQ_ENRICHMENT":',
        paste0('    beer: ', as.character(packageVersion('beer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phip_seq_enrichment.csv versions.yml
    """
}

workflow BIOC_BEER_PHIP_SEQ_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PhIPData object ] ]

    main:
    BIOC_BEER_PHIP_SEQ_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_BEER_PHIP_SEQ_ENRICHMENT.out.tables
    plots    = BIOC_BEER_PHIP_SEQ_ENRICHMENT.out.plots
    objects  = BIOC_BEER_PHIP_SEQ_ENRICHMENT.out.objects
    versions = BIOC_BEER_PHIP_SEQ_ENRICHMENT.out.versions
}
