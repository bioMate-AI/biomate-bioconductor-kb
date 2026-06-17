#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EDASeq — gene_level_normalization_and_de
// Perform gene-level exploratory data analysis, within-lane and between-lane normalization, and prepare data for differential expression analysis.
// Input: geneLevelData, yeastGC, yeastLength
// Container: quay.io/biocontainers/bioconductor-edaseq:2.44.0--r45hdfd78af_0
// R packages: DESeq2, EDASeq, edgeR
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, EDASeq, edgeR
// Visualizations: box plot
// QC: dispersion/size-factor estimation, low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load User Input Files
//  * 2. [Visualization & Output] Filter and Align Gene Metadata
//  * 3. [Visualization & Output] Create SeqExpressionSet Object
//  * 4. [Visualization & Output] Exploratory Plotting
//  * 5. [Visualization & Output] Normalization (Within-lane and Between-lane)
//  * 6. [Visualization & Output] Generate Normalization Offsets
//  * 7. [Visualization & Output] Differential Expression Analysis: edgeR
//  * 8. [Visualization & Output] Differential Expression Analysis: DESeq2
//  * 9. [Visualization & Output] Unrounded Normalization & Verification
//  * 10. [Visualization & Output] Optional: Retrieve Gene Length and GC Content

nextflow.enable.dsl = 2

process BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE {
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
    .bm_deps <- c("DESeq2", "EDASeq", "edgeR")
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
            library(EDASeq)
            library(edgeR)
            library(DESeq2)
            
            # Define colors for plotting (as defined in the EDASeq vignette)
            colors <- c(rep(rgb(1,0,0,alpha=0.7),2),
                        rep(rgb(0,0,1,alpha=0.7),2),
                        rep(rgb(0,1,0,alpha=0.7),2),
                        rep(rgb(0,1,1,alpha=0.7),2))
            
            # ==========================================
            # --- Load User Input Files ---
            # ==========================================
            
            load_input <- function(var_name) {
              rds_path <- paste0(var_name, ".rds")
              csv_path <- paste0(var_name, ".csv")
              tsv_path <- paste0(var_name, ".tsv")
              txt_path <- paste0(var_name, ".txt")
              
              if (file.exists(rds_path)) {
                return(readRDS(rds_path))
              } else if (file.exists(csv_path)) {
                df <- read.csv(csv_path, row.names = 1, check.names = FALSE)
                if (ncol(df) == 1 && var_name != "geneLevelData") {
                  vec <- df[[1]]
                  names(vec) <- rownames(df)
                  return(vec)
                }
                return(as.matrix(df))
              } else if (file.exists(tsv_path)) {
                df <- read.delim(tsv_path, row.names = 1, check.names = FALSE)
                if (ncol(df) == 1 && var_name != "geneLevelData") {
                  vec <- df[[1]]
                  names(vec) <- rownames(df)
                  return(vec)
                }
                return(as.matrix(df))
              } else if (file.exists(txt_path)) {
                df <- read.table(txt_path, header = TRUE, row.names = 1, check.names = FALSE)
                if (ncol(df) == 1 && var_name != "geneLevelData") {
                  vec <- df[[1]]
                  names(vec) <- rownames(df)
                  return(vec)
                }
                return(as.matrix(df))
              } else if (file.exists(var_name)) {
                res <- tryCatch(readRDS(var_name), error = function(e) NULL)
                if (!is.null(res)) return(res)
                df <- tryCatch(read.table(var_name, header = TRUE, row.names = 1, check.names = FALSE), error = function(e) NULL)
                if (!is.null(df)) {
                  if (ncol(df) == 1 && var_name != "geneLevelData") {
                    vec <- df[[1]]
                    names(vec) <- rownames(df)
                    return(vec)
                  }
                  return(as.matrix(df))
                }
              }
              stop(paste("Could not find or read input file for:", var_name))
            }
            
            message("Loading input files...")
            geneLevelData <- load_input("geneLevelData")
            yeastGC <- load_input("yeastGC")
            yeastLength <- load_input("yeastLength")
            
            # ==========================================
            # --- Filter and Align Gene Metadata ---
            # ==========================================
            
            message("Filtering low-count genes and aligning metadata...")
            filter <- apply(geneLevelData, 1, function(x) mean(x) > 10)
            print(table(filter))
            
            common_features <- intersect(names(yeastGC), names(yeastLength))
            common <- intersect(common_features, rownames(geneLevelData[filter, ]))
            message(paste("Number of common genes:", length(common)))
            
            # ==========================================
            # --- Create SeqExpressionSet Object ---
            # ==========================================
            
            message("Creating SeqExpressionSet...")
            feature <- data.frame(gc = yeastGC[common_features], 
                                  length = yeastLength[common_features], 
                                  row.names = common_features)
            
            n_samples <- ncol(geneLevelData)
            n_mut <- floor(n_samples / 2)
            n_wt <- n_samples - n_mut
            
            data <- newSeqExpressionSet(counts = as.matrix(geneLevelData[common, ]),
                                        featureData = feature[common, ],
                                        phenoData = data.frame(
                                          conditions = factor(c(rep("mut", n_mut), rep("wt", n_wt))),
                                          row.names = colnames(geneLevelData)))
            print(data)
            
            # Inspecting the object
            print(head(counts(data)))
            print(pData(data))
            print(head(fData(data)))
            print(head(offst(data)))
            
            # ==========================================
            # --- Exploratory Plotting ---
            # ==========================================
            
            message("Generating exploratory plots...")
            pdf("EDASeq_plots.pdf", width = 8, height = 8)
            
            # Boxplot of raw counts
            boxplot(data, col = colors[1:4], main = "Raw Counts Boxplot")
            
            # Mean-Difference Plot
            idx2 <- min(3, ncol(data))
            MDPlot(data, c(1, idx2))
            
            # Mean-Variance Plots
            meanVarPlot(data[, 1:2], log = TRUE, ylim = c(0, 16))
            meanVarPlot(data, log = TRUE, ylim = c(0, 16))
            
            # Bias Plot (GC-content)
            biasPlot(data, "gc", log = TRUE, ylim = c(1, 5))
            
            # Bias Boxplot
            lfc <- log(counts(data)[, idx2] + 0.1) - log(counts(data)[, 1] + 0.1)
            biasBoxplot(lfc, fData(data)\$gc)
            
            # ==========================================
            # --- Normalization (Within-lane and Between-lane) ---
            # ==========================================
            
            message("Performing within-lane and between-lane normalization...")
            dataWithin <- withinLaneNormalization(data, "gc", which = "full")
            dataNorm <- betweenLaneNormalization(dataWithin, which = "full")
            
            # Post-normalization plots
            biasPlot(dataNorm, "gc", log = TRUE, ylim = c(1, 5))
            boxplot(dataNorm, col = colors, main = "Normalized Counts Boxplot")
            
            # Save normalized counts
            write.csv(counts(dataNorm), "normalized_counts.csv", row.names = TRUE)
            saveRDS(dataNorm, "dataNorm.rds")
            
            # ==========================================
            # --- Generate Normalization Offsets ---
            # ==========================================
            
            message("Generating normalization offsets...")
            dataOffset <- withinLaneNormalization(data, "gc", which = "full", offset = TRUE)
            dataOffset <- betweenLaneNormalization(dataOffset, which = "full", offset = TRUE)
            saveRDS(dataOffset, "dataOffset.rds")
            
            # ==========================================
            # --- Differential Expression Analysis: edgeR ---
            # ==========================================
            
            message("Running edgeR analysis...")
            design <- model.matrix(~conditions, data = pData(dataOffset))
            
            y <- DGEList(counts = counts(dataOffset),
                         group = pData(dataOffset)\$conditions)
            y\$offset <- -offst(dataOffset)
            y <- estimateDisp(y, design)
            
            fit <- glmFit(y, design)
            lrt <- glmLRT(fit, coef = 2)
            print(topTags(lrt))
            
            # Save edgeR results
            write.csv(as.data.frame(topTags(lrt, n = Inf)), "edgeR_results.csv", row.names = TRUE)
            
            # ==========================================
            # --- Differential Expression Analysis: DESeq2 ---
            # ==========================================
            
            message("Running DESeq2 analysis...")
            dds <- DESeqDataSetFromMatrix(countData = counts(dataOffset),
                                          colData = pData(dataOffset),
                                          design = ~ conditions)
            
            normFactors <- exp(-1 * offst(dataOffset))
            normFactors <- normFactors / exp(rowMeans(log(normFactors)))
            normalizationFactors(dds) <- normFactors
            
            dds <- DESeq(dds)
            res <- results(dds)
            print(res)
            
            # Save DESeq2 results
            write.csv(as.data.frame(res), "DESeq2_results.csv", row.names = TRUE)
            
            # ==========================================
            # --- Unrounded Normalization & Verification ---
            # ==========================================
            
            message("Verifying unrounded normalization and offset calculations...")
            dataNorm_unrounded <- betweenLaneNormalization(data, round = FALSE, offset = TRUE)
            
            norm1 <- normCounts(dataNorm_unrounded)
            norm2 <- exp(log(counts(dataNorm_unrounded) + 0.1) + offst(dataNorm_unrounded)) - 0.1
            
            print(head(norm1 - norm2))
            print(head(round(normCounts(dataNorm_unrounded)) - round(counts(dataNorm_unrounded) * exp(offst(dataNorm_unrounded)))))
            
            # Close PDF device
            dev.off()
            message("Plots saved to 'EDASeq_plots.pdf'")
            
            # ==========================================
            # --- Optional: Retrieve Gene Length and GC Content ---
            # ==========================================
            
            message("Running optional gene length and GC content retrieval steps...")
            
            tryCatch({
              test_retrieval <- getGeneLengthAndGCContent(id = c("ENSG00000012048", "ENSG00000139618"), org = "hsa")
              print(test_retrieval)
            }, error = function(e) {
              message("Skipping human gene metadata retrieval (requires internet/biomaRt): ", e\$message)
            })
            
            message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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
      process = "BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE":',
        paste0('    EDASeq: ', as.character(packageVersion('EDASeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_level_normalization_and_de.csv versions.yml
    """
}

workflow BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneLevelData, yeastGC, yeastLength ] ]

    main:
    BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE(ch_input)

    emit:
    tables   = BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE.out.tables
    plots    = BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE.out.plots
    objects  = BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE.out.objects
    versions = BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE.out.versions
}
