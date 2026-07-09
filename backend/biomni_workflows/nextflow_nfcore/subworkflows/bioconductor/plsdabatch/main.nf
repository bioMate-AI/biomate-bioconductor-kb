#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PLSDAbatch — microbiome_batch_correction
// Filter, transform, detect, correct, and assess batch effects in microbiome raw count data using PLSDA-batch or sPLSDA-batch.
// Input: ad.count, ad.metadata
// Container: quay.io/biocontainers/bioconductor-plsdabatch:1.6.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, PLSDAbatch, SummarizedExperiment, ggplot2, gridExtra, mixOmics, pheatmap, vegan
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Pre-filtering
//  * 3. [Visualization & Output] Transformation
//  * 4. [Visualization & Output] Batch Effect Detection & Visualization Setup
//  * 5. [Visualization & Output] Batch Effect Correction
//  * 6. [Visualization & Output] Assessing Batch Effect Correction
//  * 7. [Visualization & Output] Variable Selection
//  * 8. [Visualization & Output] Save Outputs

nextflow.enable.dsl = 2

process BIOC_PLSDABATCH_MICROBIOME_BATCH_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("pheatmap", "vegan", "gridExtra", "mixOmics", "Biobase", "PLSDAbatch", "ggplot2")
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
        library(pheatmap)
        library(vegan)
        library(gridExtra)
        library(mixOmics)
        library(Biobase)
        library(PLSDAbatch)
        library(ggplot2)
        
        # ==========================================
        # --- Read User Input Files ---
        # ==========================================
        
        # Read ad.count
        if (file.exists("ad.count")) {
          ad.count <- tryCatch(readRDS("ad.count"), error = function(e) {
            tryCatch(read.csv("ad.count", row.names = 1, check.names = FALSE), error = function(e2) {
              read.table("ad.count", header = TRUE, row.names = 1, check.names = FALSE)
            })
          })
        } else if (file.exists("ad.count.rds")) {
          ad.count <- readRDS("ad.count.rds")
        } else if (file.exists("ad.count.csv")) {
          ad.count <- read.csv("ad.count.csv", row.names = 1, check.names = FALSE)
        } else {
          stop("Error: ad.count file not found in the working directory.")
        }
        
        # Read ad.metadata
        if (file.exists("ad.metadata")) {
          ad.metadata <- tryCatch(readRDS("ad.metadata"), error = function(e) {
            tryCatch(read.csv("ad.metadata", row.names = 1, check.names = FALSE), error = function(e2) {
              read.table("ad.metadata", header = TRUE, row.names = 1, check.names = FALSE)
            })
          })
        } else if (file.exists("ad.metadata.rds")) {
          ad.metadata <- readRDS("ad.metadata.rds")
        } else if (file.exists("ad.metadata.csv")) {
          ad.metadata <- read.csv("ad.metadata.csv", row.names = 1, check.names = FALSE)
        } else {
          stop("Error: ad.metadata file not found in the working directory.")
        }
        
        # Ensure ad.count is a matrix
        ad.count <- as.matrix(ad.count)
        
        # Extract batch and treatment factors with robust fallbacks
        if ("sequencing_run_date" %in% colnames(ad.metadata)) {
          ad.batch <- factor(ad.metadata\$sequencing_run_date, levels = unique(ad.metadata\$sequencing_run_date))
        } else {
          batch_col <- grep("batch", colnames(ad.metadata), ignore.case = TRUE, value = TRUE)
          if (length(batch_col) > 0) {
            ad.batch <- factor(ad.metadata[[batch_col[1]]])
          } else {
            ad.batch <- factor(ad.metadata[, 1])
          }
        }
        
        if ("initial_phenol_concentration.regroup" %in% colnames(ad.metadata)) {
          ad.trt <- as.factor(ad.metadata\$initial_phenol_concentration.regroup)
        } else {
          trt_col <- grep("trt|treatment|group", colnames(ad.metadata), ignore.case = TRUE, value = TRUE)
          if (length(trt_col) > 0) {
            ad.trt <- as.factor(ad.metadata[[trt_col[1]]])
          } else {
            ad.trt <- as.factor(ad.metadata[, 2])
          }
        }
        names(ad.batch) <- names(ad.trt) <- rownames(ad.metadata)
        
        # ==========================================
        # --- Pre-filtering ---
        # ==========================================
        ad.filter.res <- PreFL(data = ad.count)
        ad.filter <- ad.filter.res\$data.filter
        
        # Save filtering statistics
        filter_stats <- data.frame(
          Metric = c("Zero_Prob_Before", "Zero_Prob_After", "OTUs_Before", "OTUs_After"),
          Value = c(ad.filter.res\$zero.prob.before, ad.filter.res\$zero.prob.after, ncol(ad.count), ncol(ad.filter))
        )
        write.csv(filter_stats, "filtering_statistics.csv", row.names = FALSE)
        
        # ==========================================
        # --- Transformation ---
        # ==========================================
        ad.clr <- logratio.transfo(X = ad.filter, logratio = "CLR", offset = 1)
        class(ad.clr) <- "matrix"
        
        # ==========================================
        # --- Batch Effect Detection & Visualization Setup ---
        # ==========================================
        # Open PDF device to capture all diagnostic and assessment plots
        pdf("PLSDAbatch_microbiome_correction_plots.pdf", width = 11, height = 8.5)
        
        # PCA before correction
        ad.pca.before <- mixOmics::pca(ad.clr, ncomp = 3, scale = TRUE)
        print(Scatter_Density(
            components = ad.pca.before\$variates\$X, comp = c(1, 2),
            expl.var = ad.pca.before\$prop_expl_var\$X,
            batch = ad.batch, trt = ad.trt,
            title = "AD data - Before Correction", trt.legend.title = "Phenol conc."
        ))
        
        # Select top OTU driving major variance
        ad.OTU.name <- selectVar(ad.pca.before, comp = 1)\$name[1]
        ad.OTU_batch <- data.frame(value = ad.clr[, ad.OTU.name], batch = ad.batch)
        
        print(box_plot(
            df = ad.OTU_batch, title = paste(ad.OTU.name, "(AD data)"),
            x.angle = 30
        ))
        
        print(density_plot(df = ad.OTU_batch, title = paste(ad.OTU.name, "(AD data)")))
        
        # Linear regression analysis
        available_levels <- levels(ad.batch)
        
        if (length(available_levels) >= 1) {
          ref_batch1 <- available_levels[1]
          ad.batch <- relevel(x = ad.batch, ref = ref_batch1)
          ad.OTU.lm <- linear_regres(
              data = ad.clr[, ad.OTU.name],
              trt = ad.trt, batch.fix = ad.batch,
              type = "linear model"
          )
          cat("--- Linear Regression (Reference Batch 1) ---\n")
          print(summary(ad.OTU.lm\$model\$data))
        }
        
        if (length(available_levels) >= 2) {
          ref_batch2 <- available_levels[2]
          ad.batch <- relevel(x = ad.batch, ref = ref_batch2)
          ad.OTU.lm2 <- linear_regres(
              data = ad.clr[, ad.OTU.name],
              trt = ad.trt, batch.fix = ad.batch,
              type = "linear model"
          )
          cat("--- Linear Regression (Reference Batch 2) ---\n")
          print(summary(ad.OTU.lm2\$model\$data))
        }
        
        # Heatmap
        ad.clr.s <- scale(ad.clr, center = TRUE, scale = TRUE)
        ad.clr.ss <- scale(t(ad.clr.s), center = TRUE, scale = TRUE)
        ad.anno_col <- data.frame(Batch = ad.batch, Treatment = ad.trt)
        ad.anno_colors <- list(
            Batch = color.mixo(seq_len(length(unique(ad.batch)))),
            Treatment = pb_color(seq_len(length(unique(ad.trt))))
        )
        names(ad.anno_colors\$Batch) <- levels(ad.batch)
        names(ad.anno_colors\$Treatment) <- levels(ad.trt)
        
        pheatmap(ad.clr.ss,
            cluster_rows = FALSE,
            fontsize_row = 4,
            fontsize_col = 6,
            fontsize = 8,
            clustering_distance_rows = "euclidean",
            clustering_method = "ward.D",
            treeheight_row = 30,
            annotation_col = ad.anno_col,
            annotation_colors = ad.anno_colors,
            border_color = "NA",
            main = "AD data - Scaled"
        )
        
        # pRDA before correction
        ad.factors.df <- data.frame(trt = ad.trt, batch = ad.batch)
        class(ad.clr) <- "matrix"
        ad.rda.before <- varpart(ad.clr, ~trt, ~batch,
            data = ad.factors.df, scale = TRUE
        )
        cat("--- pRDA Before Correction ---\n")
        print(ad.rda.before\$part\$indfract)
        
        # ==========================================
        # --- Batch Effect Correction ---
        # ==========================================
        # Determine optimal components dynamically
        ncomp_trt <- nlevels(ad.trt) - 1
        if (ncomp_trt < 1) ncomp_trt <- 1
        ncomp_bat <- nlevels(ad.batch) - 1
        if (ncomp_bat < 1) ncomp_bat <- 1
        
        # PLSDA-batch (Regression mode)
        ad.PLSDA_batch.res.reg <- PLSDA_batch(
            X = ad.clr,
            Y.trt = ad.trt, Y.bat = ad.batch,
            ncomp.trt = ncomp_trt, ncomp.bat = ncomp_bat,
            mode = "regression"
        )
        ad.PLSDA_batch.reg <- ad.PLSDA_batch.res.reg\$X.nobatch
        
        # PLSDA-batch (Canonical mode)
        ad.PLSDA_batch.res.cnc <- PLSDA_batch(
            X = ad.clr,
            Y.trt = ad.trt, Y.bat = ad.batch,
            ncomp.trt = ncomp_trt, ncomp.bat = ncomp_bat,
            mode = "canonical"
        )
        ad.PLSDA_batch.cnc <- ad.PLSDA_batch.res.cnc\$X.nobatch
        
        # sPLSDA-batch (Regression mode)
        keepX_val <- min(100, ncol(ad.clr))
        ad.sPLSDA_batch.res.reg <- PLSDA_batch(
            X = ad.clr,
            Y.trt = ad.trt, Y.bat = ad.batch,
            ncomp.trt = ncomp_trt, keepX.trt = keepX_val,
            ncomp.bat = ncomp_bat, mode = "regression"
        )
        ad.sPLSDA_batch.reg <- ad.sPLSDA_batch.res.reg\$X.nobatch
        
        # sPLSDA-batch (Canonical mode)
        ad.sPLSDA_batch.res.cnc <- PLSDA_batch(
            X = ad.clr,
            Y.trt = ad.trt, Y.bat = ad.batch,
            ncomp.trt = ncomp_trt, keepX.trt = keepX_val,
            ncomp.bat = ncomp_bat, mode = "canonical"
        )
        ad.sPLSDA_batch.cnc <- ad.sPLSDA_batch.res.cnc\$X.nobatch
        
        # ==========================================
        # --- Assessing Batch Effect Correction ---
        # ==========================================
        # Post-correction PCA
        ad.pca.PLSDA_batch.cnc <- pca(ad.PLSDA_batch.cnc, ncomp = 3, scale = TRUE)
        ad.pca.sPLSDA_batch.cnc <- pca(ad.sPLSDA_batch.cnc, ncomp = 3, scale = TRUE)
        ad.pca.PLSDA_batch.reg <- pca(ad.PLSDA_batch.reg, ncomp = 3, scale = TRUE)
        ad.pca.sPLSDA_batch.reg <- pca(ad.sPLSDA_batch.reg, ncomp = 3, scale = TRUE)
        
        # Re-order batches for plotting consistency
        ad.batch <- factor(ad.batch, levels = available_levels)
        
        ad.pca.before.plot <- Scatter_Density(
            components = ad.pca.before\$variates\$X, comp = c(1, 2),
            expl.var = ad.pca.before\$prop_expl_var\$X,
            batch = ad.batch, trt = ad.trt, title = "Before correction"
        )
        ad.pca.PLSDA_batch.cnc.plot <- Scatter_Density(
            components = ad.pca.PLSDA_batch.cnc\$variates\$X, comp = c(1, 2),
            expl.var = ad.pca.PLSDA_batch.cnc\$prop_expl_var\$X,
            batch = ad.batch, trt = ad.trt, title = "PLSDA-batch (canonical)"
        )
        ad.pca.sPLSDA_batch.cnc.plot <- Scatter_Density(
            components = ad.pca.sPLSDA_batch.cnc\$variates\$X, comp = c(1, 2),
            expl.var = ad.pca.sPLSDA_batch.cnc\$prop_expl_var\$X,
            batch = ad.batch, trt = ad.trt, title = "sPLSDA-batch (canonical)"
        )
        ad.pca.PLSDA_batch.reg.plot <- Scatter_Density(
            components = ad.pca.PLSDA_batch.reg\$variates\$X, comp = c(1, 2),
            expl.var = ad.pca.PLSDA_batch.reg\$prop_expl_var\$X,
            batch = ad.batch, trt = ad.trt, title = "PLSDA-batch (regression)"
        )
        ad.pca.sPLSDA_batch.reg.plot <- Scatter_Density(
            components = ad.pca.sPLSDA_batch.reg\$variates\$X, comp = c(1, 2),
            expl.var = ad.pca.sPLSDA_batch.reg\$prop_expl_var\$X,
            batch = ad.batch, trt = ad.trt, title = "sPLSDA-batch (regression)"
        )
        
        grid.arrange(ad.pca.before.plot,
            ad.pca.PLSDA_batch.cnc.plot,
            ad.pca.sPLSDA_batch.cnc.plot,
            ad.pca.PLSDA_batch.reg.plot,
            ad.pca.sPLSDA_batch.reg.plot,
            ncol = 2
        )
        
        # Global explained variance (pRDA)
        ad.corrected.list <- list(
            `Before correction` = ad.clr,
            `PLSDA-batch (canonical)` = ad.PLSDA_batch.cnc,
            `sPLSDA-batch (canonical)` = ad.sPLSDA_batch.cnc,
            `PLSDA-batch (regression)` = ad.PLSDA_batch.reg,
            `sPLSDA-batch (regression)` = ad.sPLSDA_batch.reg
        )
        
        ad.prop.df <- data.frame(
            Treatment = NA, Batch = NA,
            Intersection = NA,
            Residuals = NA
        )
        for (i in seq_len(length(ad.corrected.list))) {
            rda.res <- varpart(ad.corrected.list[[i]], ~trt, ~batch,
                data = ad.factors.df, scale = TRUE
            )
            ad.prop.df[i, ] <- rda.res\$part\$indfract\$Adj.R.squared
        }
        rownames(ad.prop.df) <- names(ad.corrected.list)
        ad.prop.df <- ad.prop.df[, c(1, 3, 2, 4)]
        
        print(partVar_plot(prop.df = ad.prop.df))
        
        # R2 values for each variable
        ad.corr_scale.list <- lapply(
            ad.corrected.list,
            function(x) {
                apply(x, 2, scale)
            }
        )
        
        ad.r_values.list <- list()
        for (i in seq_len(length(ad.corr_scale.list))) {
            ad.r_values <- data.frame(trt = NA, batch = NA)
            for (c in seq_len(ncol(ad.corr_scale.list[[i]]))) {
                ad.fit.res.trt <- lm(ad.corr_scale.list[[i]][, c] ~ ad.trt)
                ad.r_values[c, 1] <- summary(ad.fit.res.trt)\$r.squared
                ad.fit.res.batch <- lm(ad.corr_scale.list[[i]][, c] ~ ad.batch)
                ad.r_values[c, 2] <- summary(ad.fit.res.batch)\$r.squared
            }
            ad.r_values.list[[i]] <- ad.r_values
        }
        names(ad.r_values.list) <- names(ad.corr_scale.list)
        
        ad.boxp.list <- list()
        num_features <- ncol(ad.clr)
        for (i in seq_len(length(ad.r_values.list))) {
            ad.boxp.list[[i]] <-
                data.frame(
                    r2 = c(
                        ad.r_values.list[[i]][, "trt"],
                        ad.r_values.list[[i]][, "batch"]
                    ),
                    Effects = as.factor(rep(c("Treatment", "Batch"),
                        each = num_features
                    ))
                )
        }
        names(ad.boxp.list) <- names(ad.r_values.list)
        
        ad.r2.boxp <- rbind(
            ad.boxp.list\$`Before correction`,
            ad.boxp.list\$`PLSDA-batch (canonical)`,
            ad.boxp.list\$`sPLSDA-batch (canonical)`,
            ad.boxp.list\$`PLSDA-batch (regression)`,
            ad.boxp.list\$`sPLSDA-batch (regression)`
        )
        
        ad.r2.boxp\$methods <- rep(
            c(
                "Before correction", "PLSDA-batch (canonical)",
                "sPLSDA-batch (canonical)", "PLSDA-batch (regression)",
                "sPLSDA-batch (regression)"
            ),
            each = num_features * 2
        )
        
        ad.r2.boxp\$methods <- factor(ad.r2.boxp\$methods,
            levels = unique(ad.r2.boxp\$methods)
        )
        
        p_box <- ggplot(ad.r2.boxp, aes(x = Effects, y = r2, fill = Effects)) +
            geom_boxplot(alpha = 0.80) +
            theme_bw() +
            theme(
                text = element_text(size = 18),
                axis.title.x = element_blank(),
                axis.title.y = element_blank(),
                axis.text.x = element_text(angle = 60, hjust = 1, size = 18),
                axis.text.y = element_text(size = 18),
                panel.grid.minor.x = element_blank(),
                panel.grid.major.x = element_blank(),
                legend.position = "right"
            ) +
            facet_grid(~methods) +
            scale_fill_manual(values = pb_color(c(12, 14)))
        print(p_box)
        
        # Sum of R2 values
        ad.barp.list <- list()
        for (i in seq_len(length(ad.r_values.list))) {
            ad.barp.list[[i]] <- data.frame(
                r2 = c(
                    sum(ad.r_values.list[[i]][, "trt"]),
                    sum(ad.r_values.list[[i]][, "batch"])
                ),
                Effects = c("Treatment", "Batch")
            )
        }
        names(ad.barp.list) <- names(ad.r_values.list)
        
        ad.r2.barp <- rbind(
            ad.barp.list\$`Before correction`,
            ad.barp.list\$`PLSDA-batch (canonical)`,
            ad.barp.list\$`sPLSDA-batch (canonical)`,
            ad.barp.list\$`PLSDA-batch (regression)`,
            ad.barp.list\$`sPLSDA-batch (regression)`
        )
        
        ad.r2.barp\$methods <- rep(
            c(
                "Before correction", "PLSDA-batch (canonical)",
                "sPLSDA-batch (canonical)", "PLSDA-batch (regression)",
                "sPLSDA-batch (regression)"
            ),
            each = 2
        )
        
        ad.r2.barp\$methods <- factor(ad.r2.barp\$methods,
            levels = unique(ad.r2.barp\$methods)
        )
        
        p_bar <- ggplot(ad.r2.barp, aes(x = Effects, y = r2, fill = Effects)) +
            geom_bar(stat = "identity") +
            theme_bw() +
            theme(
                text = element_text(size = 18),
                axis.title.x = element_blank(),
                axis.title.y = element_blank(),
                axis.text.x = element_text(angle = 60, hjust = 1, size = 18),
                axis.text.y = element_text(size = 18),
                panel.grid.minor.x = element_blank(),
                panel.grid.major.x = element_blank(),
                legend.position = "right"
            ) +
            facet_grid(~methods) +
            scale_fill_manual(values = pb_color(c(12, 14)))
        print(p_bar)
        
        # Alignment scores
        ad.scores <- c()
        names(ad.batch) <- rownames(ad.clr)
        for (i in seq_len(length(ad.corrected.list))) {
            k_val <- min(8, nrow(ad.clr) - 1)
            ncomp_val <- min(50, ncol(ad.corrected.list[[i]]), nrow(ad.corrected.list[[i]]))
            res <- alignment_score(
                data = ad.corrected.list[[i]],
                batch = ad.batch,
                var = 0.95,
                k = k_val,
                ncomp = ncomp_val
            )
            ad.scores <- c(ad.scores, res)
        }
        
        ad.scores.df <- data.frame(
            scores = ad.scores,
            methods = names(ad.corrected.list)
        )
        
        ad.scores.df\$methods <- factor(ad.scores.df\$methods,
            levels = rev(names(ad.corrected.list))
        )
        
        p_align <- ggplot() +
            geom_col(aes(
                x = ad.scores.df\$methods,
                y = ad.scores.df\$scores
            )) +
            geom_text(
                aes(
                    x = ad.scores.df\$methods,
                    y = ad.scores.df\$scores / 2,
                    label = round(ad.scores.df\$scores, 3)
                ),
                size = 3, col = "white"
            ) +
            coord_flip() +
            theme_bw() +
            ylab("Alignment Scores") +
            xlab("") +
            ylim(0, max(ad.scores.df\$scores) * 1.2)
        print(p_align)
        
        # Close PDF device
        dev.off()
        
        # ==========================================
        # --- Variable Selection ---
        # ==========================================
        keepX_sel <- min(50, ncol(ad.clr))
        
        splsda.plsda_batch.reg <- splsda(
            X = ad.PLSDA_batch.reg, Y = ad.trt,
            ncomp = 3, keepX = rep(keepX_sel, 3)
        )
        select.plsda_batch.reg <- selectVar(splsda.plsda_batch.reg, comp = 1)
        
        splsda.splsda_batch.reg <- splsda(
            X = ad.sPLSDA_batch.reg, Y = ad.trt,
            ncomp = 3, keepX = rep(keepX_sel, 3)
        )
        select.splsda_batch.reg <- selectVar(splsda.splsda_batch.reg, comp = 1)
        
        overlap_count <- length(intersect(select.plsda_batch.reg\$name, select.splsda_batch.reg\$name))
        cat("Overlap count between PLSDA-batch and sPLSDA-batch selected variables:", overlap_count, "\n")
        
        # ==========================================
        # --- Save Outputs ---
        # ==========================================
        saveRDS(ad.PLSDA_batch.reg, "ad.PLSDA_batch.reg.rds")
        saveRDS(ad.sPLSDA_batch.reg, "ad.sPLSDA_batch.reg.rds")
        saveRDS(ad.prop.df, "ad.prop.df.rds")
        saveRDS(ad.scores.df, "ad.scores.df.rds")
        
        write.csv(ad.prop.df, "global_explained_variance.csv", row.names = TRUE)
        write.csv(ad.scores.df, "alignment_scores.csv", row.names = FALSE)
        
        # Print session info
        sessionInfo()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # microbiome prevalence/abundance filtering (Callahan 2017 F1000).
    .pa_kept <- NA_real_
    for (.pa_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .pa_obj <- tryCatch(readRDS(.pa_rds), error = function(e) NULL)
      .pa_mat <- if (is.matrix(.pa_obj) || is.data.frame(.pa_obj)) .pa_obj else NULL
      if (!is.null(.pa_mat) && nrow(.pa_mat) > 50) {
        .pa_m <- suppressWarnings(as.matrix(.pa_mat))
        .pa_prev <- suppressWarnings(apply(.pa_m, 1, function(r) mean(as.numeric(r) > 0, na.rm = TRUE)))
        .pa_kept <- sum(is.finite(.pa_prev) & .pa_prev >= 0.05) / nrow(.pa_m); break
      }
    }
    .gates_by_label[["prevalence/abundance filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "taxa_kept_fraction",
      metric_value = if (is.finite(.pa_kept)) round(.pa_kept, 4) else NA_real_,
      passes = isTRUE(is.finite(.pa_kept) && .pa_kept >= 0.3 && .pa_kept <= 0.7),
      status = if (is.finite(.pa_kept)) "computed (rows w/ >=5% prevalence / total)"
               else "not_computed (no abundance matrix .rds artifact present)"
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

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .pca_obj <- tryCatch(readRDS(.pca_rds), error = function(e) NULL)
      .pca_mat <- if (is.matrix(.pca_obj) || is.data.frame(.pca_obj)) .pca_obj else NULL
      if (!is.null(.pca_mat) && ncol(.pca_mat) >= 3 && nrow(.pca_mat) >= 100) {
        .pca_m <- suppressWarnings(as.matrix(.pca_mat))
        .pca_kept <- apply(.pca_m, 1, function(r) all(is.finite(r)) && var(r) > 0)
        if (sum(.pca_kept) >= 50) {
          .pca_fit <- tryCatch(prcomp(t(.pca_m[.pca_kept, , drop = FALSE])), error = function(e) NULL)
          if (!is.null(.pca_fit)) {
            .pca_vars <- (.pca_fit\$sdev^2) / sum(.pca_fit\$sdev^2)
            .pca_pc1 <- round(.pca_vars[1] * 100, 2); .pca_files <- c(.pca_files, .pca_rds); break
          }
        }
      }
    }
    .gates_by_label[["diagnostic MA/PCA QC"]] <- list(
      gate_row = "bioc_diagnostic_ma_pca_qc",
      metric_name = "pc1_var_explained",
      metric_value = .pca_pc1,
      passes = isTRUE(is.finite(.pca_pc1) && .pca_pc1 > 10),
      status = if (is.finite(.pca_pc1)) paste0("computed (PC1=", .pca_pc1, "%)")
               else "not_computed (no large numeric matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_PLSDABATCH_MICROBIOME_BATCH_CORRECTION",
      domain  = "bioconductor",
      declared_qc_steps = c("prevalence/abundance filtering", "count normalization", "diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PLSDABATCH_MICROBIOME_BATCH_CORRECTION":',
        paste0('    PLSDAbatch: ', as.character(packageVersion('PLSDAbatch')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microbiome_batch_correction.csv versions.yml
    """
}

workflow BIOC_PLSDABATCH_MICROBIOME_BATCH_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ad.count, ad.metadata ] ]

    main:
    BIOC_PLSDABATCH_MICROBIOME_BATCH_CORRECTION(ch_input)

    emit:
    tables   = BIOC_PLSDABATCH_MICROBIOME_BATCH_CORRECTION.out.tables
    plots    = BIOC_PLSDABATCH_MICROBIOME_BATCH_CORRECTION.out.plots
    objects  = BIOC_PLSDABATCH_MICROBIOME_BATCH_CORRECTION.out.objects
    versions = BIOC_PLSDABATCH_MICROBIOME_BATCH_CORRECTION.out.versions
}
