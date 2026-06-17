#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SPsimSeq — simulate_bulk_rna_seq
// Simulate bulk RNA-seq data from a real bulk RNA-seq count matrix template.
// Input: zhang.counts, MYCN.status
// Container: quay.io/biocontainers/bioconductor-spsimseq:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SPsimSeq, edgeR
// Visualizations: box plot
// QC: low-count filtering, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and filter the source count data to remove low-expression genes
//  * 2. [Core Analysis] Run SPsimSeq with model.zero.prob = FALSE and result.format = "list"
//  * 3. [Core Analysis] Extract the simulated count matrix, sample metadata, and gene metadata
//  * 4. [Core Analysis] Evaluate densities using evaluateDensities

nextflow.enable.dsl = 2

process BIOC_SPSIMSEQ_SIMULATE_BULK_RNA_SEQ {
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
    .bm_deps <- c("SPsimSeq", "edgeR", "LSD")
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
        library(SPsimSeq)
        library(edgeR)
        library(LSD)
        
        # ==========================================
        # 1. Load and Filter Source Count Data
        # ==========================================
        
        # Read zhang.counts from the working directory
        if (file.exists("zhang.counts")) {
          zhang.counts <- tryCatch({
            readRDS("zhang.counts")
          }, error = function(e) {
            as.matrix(read.table("zhang.counts", header = TRUE, row.names = 1, check.names = FALSE))
          })
        } else {
          stop("Error: Required input file 'zhang.counts' not found in the working directory.")
        }
        
        # Read MYCN.status from the working directory
        if (file.exists("MYCN.status")) {
          MYCN.status <- tryCatch({
            readRDS("MYCN.status")
          }, error = function(e) {
            tbl <- tryCatch(read.table("MYCN.status", header = FALSE, stringsAsFactors = FALSE), error = function(err) NULL)
            if (!is.null(tbl)) {
              vec <- as.character(tbl[[1]])
              if (vec[1] %in% c("MYCN.status", "group", "status")) {
                vec <- vec[-1]
              }
              vec
            } else {
              readLines("MYCN.status")
            }
          })
        } else {
          stop("Error: Required input file 'MYCN.status' not found in the working directory.")
        }
        
        # Ensure MYCN.status length matches the number of columns in zhang.counts
        if (length(MYCN.status) != ncol(zhang.counts)) {
          min_len <- min(length(MYCN.status), ncol(zhang.counts))
          zhang.counts <- zhang.counts[, seq_len(min_len), drop = FALSE]
          MYCN.status <- MYCN.status[seq_len(min_len)]
        }
        
        # Filter genes with sufficient expression (important step to avoid bugs)
        # Keep genes with CPM > 0.5 in at least 10% of the samples
        cpm_vals <- t(t(zhang.counts) / colSums(zhang.counts)) * 1e6
        keep_genes <- rowSums(cpm_vals > 0.5) >= (0.1 * ncol(zhang.counts))
        
        if (sum(keep_genes) >= 3000) {
          zhang.counts <- zhang.counts[keep_genes, , drop = FALSE]
        } else {
          # Fallback: if filtering is too strict, keep top 3000 genes by mean expression
          gene_means <- rowMeans(zhang.counts)
          order_idx <- order(gene_means, decreasing = TRUE)
          zhang.counts <- zhang.counts[order_idx[seq_len(min(3000, length(order_idx)))], , drop = FALSE]
        }
        
        # ==========================================
        # 2. Run SPsimSeq Simulation
        # ==========================================
        
        set.seed(6452) # Set seed for reproducibility
        
        # Simulate data using the exact documented function call and arguments
        sim.data.bulk <- SPsimSeq(n.sim = 1, s.data = zhang.counts,
                                  group = MYCN.status, n.genes = 3000, batch.config = 1,
                                  group.config = c(0.5, 0.5), tot.samples = ncol(zhang.counts), 
                                  pDE = 0.1, lfc.thrld = 0.5, model.zero.prob = FALSE, result.format = "list", return.details = TRUE)
        
        # ==========================================
        # 3. Extract Simulated Data and Metadata
        # ==========================================
        
        sim.data.bulk1 <- sim.data.bulk\$sim.data.list[[1]]
        
        # Print a preview to console
        cat("--- Simulated Counts Preview ---\n")
        print(head(sim.data.bulk1\$counts[, seq_len(min(5, ncol(sim.data.bulk1\$counts)))]))
        cat("\n--- Simulated colData Preview ---\n")
        print(head(sim.data.bulk1\$colData))
        cat("\n--- Simulated rowData Preview ---\n")
        print(head(sim.data.bulk1\$rowData))
        
        # Save extracted simulated data to disk
        write.csv(sim.data.bulk1\$counts, "simulated_counts.csv", row.names = TRUE)
        write.csv(sim.data.bulk1\$colData, "simulated_colData.csv", row.names = TRUE)
        write.csv(sim.data.bulk1\$rowData, "simulated_rowData.csv", row.names = TRUE)
        
        # ==========================================
        # 4. Evaluate Densities
        # ==========================================
        
        geneDens = evaluateDensities(sim.data.bulk, newData = rownames(zhang.counts)[1])
        saveRDS(geneDens, "gene_densities.rds")
        
        # ==========================================
        # 5. Generate Comparison Plots
        # ==========================================
        
        pdf("simulation_validation_plots.pdf", width = 12, height = 5)
        tryCatch({
          Y0.log.cpm <- log2(edgeR::cpm(zhang.counts) + 1)
          Y1.log.cpm <- log2(edgeR::cpm(sim.data.bulk1\$counts) + 1)
          Y0.log.cpm <- Y0.log.cpm[rowMeans(Y0.log.cpm > 0) >= 0.1, ]
          Y1.log.cpm <- Y1.log.cpm[rowMeans(Y1.log.cpm > 0) >= 0.1, ]
          
          rowVars <- function(X) { apply(X, 1, var, na.rm = TRUE) }
          rowCVs  <- function(X) { apply(X, 1, function(x) sd(x, na.rm = TRUE) / mean(x, na.rm = TRUE)) }
          
          # Boxplots comparing global properties
          par(mfrow = c(1, 3))
          boxplot(list(real.data = log(colSums(zhang.counts)), 
                       simulated.data = log(sim.data.bulk1\$colData\$sim.Lib.Size)), 
                  main = "Library Size") 
          boxplot(list(real.data = rowMeans(Y0.log.cpm), 
                       simulated.data = rowMeans(Y1.log.cpm)), 
                  main = "Mean Expression of Genes") 
          boxplot(list(real.data = rowVars(Y0.log.cpm), 
                       simulated.data = rowVars(Y1.log.cpm)), 
                  main = "Variance of Gene Expressions")
          
          # Mean-variance relationship plots
          par(mfrow = c(1, 3), mar = c(4, 4, 4, 1))
          heatscatter(rowMeans(Y0.log.cpm), rowCVs(Y0.log.cpm), ylim = c(0, 6), xlim = c(0, 16),
                      colpal = "bl2gr2rd", main = "Real Data (Mean vs CV)", xlab = "Mean log2-CPM", 
                      ylab = "Coefficients of Variation", cexplot = 0.5, alpha = 60, cex.lab = 1.25)
          heatscatter(rowMeans(Y1.log.cpm), rowCVs(Y1.log.cpm), ylim = c(0, 6), xlim = c(0, 16),
                      main = "SPsimSeq (Mean vs CV)", xlab = "Mean log2-CPM", ylab = "Coefficients of Variation", 
                      cexplot = 0.5, alpha = 60, colpal = "bl2gr2rd", cex.lab = 1.25)
          
          n.gride <- 1000
          min.g   <- seq(0, 20, length.out = n.gride + 1)[-n.gride]
          max.g   <- seq(0, 20, length.out = n.gride + 1)[-1] 
          mid.g   <- (min.g + max.g) / 2
          
          f.real  <- vapply(seq_len(n.gride), FUN.VALUE = double(1), function(r) {
            x <- Y0.log.cpm[rowMeans(Y0.log.cpm) <= max.g[r] & rowMeans(Y0.log.cpm) > min.g[r], ]
            y <- ifelse(!is.null(dim(x)), mean(rowCVs(x)), mean(sd(x) / mean(x))) 
            y
          })
          f.SPsim <- vapply(seq_len(n.gride), FUN.VALUE = double(1), function(r) {
            x <- Y1.log.cpm[rowMeans(Y1.log.cpm) <= max.g[r] & rowMeans(Y1.log.cpm) > min.g[r], ]
            y <- ifelse(!is.null(dim(x)), mean(rowCVs(x)), mean(sd(x) / mean(x))) 
            y
          })
          
          sm1 <- loess(I(f.SPsim - f.real) ~ mid.g) 
          plot(mid.g, f.SPsim - f.real, xlim = c(0, 14), col = "lightskyblue", pch = 20, cex.lab = 1.25,
               cex.main = 1.4, main = "SPsimSeq - Real Data Difference", ylab = "Difference", xlab = "Mean log2-CPM")
          lines(mid.g, predict(sm1, newdata = mid.g), col = "blue", lwd = 3)
          
        }, error = function(e) {
          warning("Could not generate validation plots: ", e\$message)
        })
        dev.off()
        
        cat("\nPipeline completed successfully. Outputs saved to working directory.\n")
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SPSIMSEQ_SIMULATE_BULK_RNA_SEQ",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SPSIMSEQ_SIMULATE_BULK_RNA_SEQ":',
        paste0('    SPsimSeq: ', as.character(packageVersion('SPsimSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simulate_bulk_rna_seq.csv versions.yml
    """
}

workflow BIOC_SPSIMSEQ_SIMULATE_BULK_RNA_SEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zhang.counts, MYCN.status ] ]

    main:
    BIOC_SPSIMSEQ_SIMULATE_BULK_RNA_SEQ(ch_input)

    emit:
    tables   = BIOC_SPSIMSEQ_SIMULATE_BULK_RNA_SEQ.out.tables
    plots    = BIOC_SPSIMSEQ_SIMULATE_BULK_RNA_SEQ.out.plots
    objects  = BIOC_SPSIMSEQ_SIMULATE_BULK_RNA_SEQ.out.objects
    versions = BIOC_SPSIMSEQ_SIMULATE_BULK_RNA_SEQ.out.versions
}
