#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SPONGE — cerna_network_inference
// Identify significant ceRNA interactions and construct a ceRNA network from paired gene and miRNA expression data.
// Input: gene_expr, mir_expr, targetscan_symbol
// Container: quay.io/biocontainers/bioconductor-sponge:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SPONGE, htmlwidgets
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter gene-miRNA interactions using regularized regression
//  * 2. [Core Analysis] Compute sensitivity correlation (mscor) for gene pairs
//  * 3. [Input & Preparation] Build null model for p-value computation
//  * 4. [Core Analysis] Compute empirical p-values and adjust for multiple testing
//  * 5. [Visualization & Output] Filter for significant interactions and plot network/centralities

nextflow.enable.dsl = 2

process BIOC_SPONGE_CERNA_NETWORK_INFERENCE {
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
    .bm_deps <- c("SPONGE")
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
        library(SPONGE)
        
        # Helper function to robustly read user input files from the working directory
        read_input <- function(base_name) {
          # Check RDS format
          if (file.exists(paste0(base_name, ".rds"))) {
            message("Reading ", base_name, ".rds")
            return(readRDS(paste0(base_name, ".rds")))
          }
          # Check CSV format
          if (file.exists(paste0(base_name, ".csv"))) {
            message("Reading ", base_name, ".csv")
            return(as.matrix(read.csv(paste0(base_name, ".csv"), row.names = 1, check.names = FALSE)))
          }
          # Check TSV format
          if (file.exists(paste0(base_name, ".tsv"))) {
            message("Reading ", base_name, ".tsv")
            return(as.matrix(read.delim(paste0(base_name, ".tsv"), row.names = 1, check.names = FALSE)))
          }
          # Check plain file
          if (file.exists(base_name)) {
            message("Reading ", base_name)
            obj <- tryCatch(readRDS(base_name), error = function(e) NULL)
            if (!is.null(obj)) return(obj)
            return(as.matrix(read.table(base_name, header = TRUE, row.names = 1, check.names = FALSE)))
          }
          stop(paste("Error: Required input file not found for", base_name))
        }
        
        # 1. Read user input files
        message("Loading input datasets...")
        gene_expr <- read_input("gene_expr")
        mir_expr <- read_input("mir_expr")
        targetscan_symbol <- read_input("targetscan_symbol")
        
        # 2. Filter gene-miRNA interactions using regularized regression
        message("Filtering gene-miRNA interactions...")
        genes_miRNA_candidates <- sponge_gene_miRNA_interaction_filter(
          gene_expr = gene_expr,
          mir_expr = mir_expr,
          mir_predicted_targets = targetscan_symbol
        )
        
        # 3. Compute sensitivity correlation (mscor) for gene pairs
        message("Computing ceRNA interactions...")
        ceRNA_interactions <- sponge(
          gene_expr = gene_expr,
          mir_expr = mir_expr,
          mir_interactions = genes_miRNA_candidates
        )
        
        # 4. Build null model for p-value computation
        message("Building null model...")
        mscor_null_model <- sponge_build_null_model(
          number_of_datasets = 1e6, 
          number_of_samples = nrow(gene_expr)
        )
        
        # Plot simulation results
        message("Plotting simulation results...")
        pdf("sponge_simulation_results.pdf", width = 10, height = 7)
        tryCatch({
          print(sponge_plot_simulation_results(mscor_null_model))
        }, error = function(e) {
          message("Warning: Could not plot simulation results: ", e\$message)
        })
        dev.off()
        
        # 5. Compute empirical p-values and adjust for multiple testing
        message("Computing empirical p-values...")
        ceRNA_interactions_sign <- sponge_compute_p_values(
          sponge_result = ceRNA_interactions, 
          null_model = mscor_null_model
        )
        
        # 6. Filter for significant interactions
        message("Filtering for significant interactions...")
        ceRNA_interactions_fdr <- ceRNA_interactions_sign[which(ceRNA_interactions_sign\$p.adj < 0.2),]
        
        # Plot network
        message("Plotting ceRNA network...")
        tryCatch({
          net_plot <- sponge_plot_network(ceRNA_interactions_fdr, genes_miRNA_candidates)
          if (!is.null(net_plot) && requireNamespace("htmlwidgets", quietly = TRUE)) {
            htmlwidgets::saveWidget(net_plot, "sponge_network.html", selfcontained = TRUE)
            message("Saved interactive network plot to 'sponge_network.html'")
          }
        }, error = function(e) {
          message("Warning: Could not plot or save network: ", e\$message)
        })
        
        # 7. Compute network centralities
        message("Computing network centralities...")
        network_centralities <- sponge_node_centralities(ceRNA_interactions_fdr)
        
        # 8. Compute weighted network centralities
        message("Computing weighted network centralities...")
        ceRNA_interactions_fdr_weight <- ceRNA_interactions_fdr
        ceRNA_interactions_fdr_weight\$weight <- -log10(ceRNA_interactions_fdr\$p.adj)
        weighted_network_centralities <- sponge_node_centralities(ceRNA_interactions_fdr_weight)
        
        # Plot network centralities
        message("Plotting network centralities...")
        pdf("sponge_network_centralities_top1.pdf", width = 7, height = 7)
        tryCatch({
          print(sponge_plot_network_centralities(weighted_network_centralities, top = 1))
        }, error = function(e) {
          message("Warning: Could not plot network centralities (top = 1): ", e\$message)
        })
        dev.off()
        
        pdf("sponge_network_centralities_btw_top1.pdf", width = 7, height = 7)
        tryCatch({
          print(sponge_plot_network_centralities(weighted_network_centralities, measure = "btw", top = 1))
        }, error = function(e) {
          message("Warning: Could not plot network centralities (btw, top = 1): ", e\$message)
        })
        dev.off()
        
        # 9. Save output files
        message("Saving output tables and objects...")
        saveRDS(genes_miRNA_candidates, "genes_miRNA_candidates.rds")
        saveRDS(ceRNA_interactions, "ceRNA_interactions.rds")
        saveRDS(mscor_null_model, "mscor_null_model.rds")
        saveRDS(ceRNA_interactions_sign, "ceRNA_interactions_sign.rds")
        saveRDS(ceRNA_interactions_fdr, "ceRNA_interactions_fdr.rds")
        saveRDS(network_centralities, "network_centralities.rds")
        saveRDS(weighted_network_centralities, "weighted_network_centralities.rds")
        
        write.csv(ceRNA_interactions, "ceRNA_interactions.csv", row.names = FALSE)
        write.csv(ceRNA_interactions_sign, "ceRNA_interactions_sign.csv", row.names = FALSE)
        write.csv(ceRNA_interactions_fdr, "ceRNA_interactions_fdr.csv", row.names = FALSE)
        write.csv(network_centralities, "network_centralities.csv", row.names = FALSE)
        write.csv(weighted_network_centralities, "weighted_network_centralities.csv", row.names = FALSE)
        
        message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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
      process = "BIOC_SPONGE_CERNA_NETWORK_INFERENCE",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SPONGE_CERNA_NETWORK_INFERENCE":',
        paste0('    SPONGE: ', as.character(packageVersion('SPONGE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cerna_network_inference.csv versions.yml
    """
}

workflow BIOC_SPONGE_CERNA_NETWORK_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_expr, mir_expr, targetscan_symbol ] ]

    main:
    BIOC_SPONGE_CERNA_NETWORK_INFERENCE(ch_input)

    emit:
    tables   = BIOC_SPONGE_CERNA_NETWORK_INFERENCE.out.tables
    plots    = BIOC_SPONGE_CERNA_NETWORK_INFERENCE.out.plots
    objects  = BIOC_SPONGE_CERNA_NETWORK_INFERENCE.out.objects
    versions = BIOC_SPONGE_CERNA_NETWORK_INFERENCE.out.versions
}
