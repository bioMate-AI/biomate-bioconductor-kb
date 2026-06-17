#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RUVSeq — ruvs_replicate_samples
// Estimate factors of unwanted variation using replicate samples where the covariates of interest are constant.
// Input: counts_matrix.csv, sample_groups.csv
// Container: quay.io/biocontainers/bioconductor-ruvseq:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EDASeq, RColorBrewer, RUVSeq
// Visualizations: PCA plot, RLE plot
// QC: diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Filter and create a SeqExpressionSet object
//  * 2. [Input & Preparation] Define replicate groups using makeGroups
//  * 3. [Core Analysis] Estimate unwanted variation factors using RUVs

nextflow.enable.dsl = 2

process BIOC_RUVSEQ_RUVS_REPLICATE_SAMPLES {
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
    .bm_deps <- c("RUVSeq", "EDASeq", "RColorBrewer")
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
        library(RUVSeq)
        library(EDASeq)
        library(RColorBrewer)
        
        # -----------------------------------------------------------------------------
        # Stage 1: Read User Input and Create SeqExpressionSet Object
        # -----------------------------------------------------------------------------
        
        # Read raw RNA-Seq read counts
        counts <- read.csv("counts_matrix.csv", row.names = 1, check.names = FALSE)
        
        # Read sample group annotations
        sample_info <- read.csv("sample_groups.csv", check.names = FALSE)
        
        # Align sample annotations with counts matrix columns
        if (all(colnames(counts) %in% sample_info[, 1])) {
          rownames(sample_info) <- sample_info[, 1]
        } else if (!all(colnames(counts) %in% rownames(sample_info))) {
          stop("Sample names in counts_matrix.csv and sample_groups.csv do not match.")
        }
        sample_info <- sample_info[colnames(counts), , drop = FALSE]
        
        # Identify the grouping covariate (replicate groups)
        group_col <- if ("group" %in% colnames(sample_info)) {
          "group"
        } else if ("x" %in% colnames(sample_info)) {
          "x"
        } else {
          colnames(sample_info)[2]
        }
        
        x <- as.factor(sample_info[[group_col]])
        
        # Filter out non-expressed genes (more than 5 reads in at least two samples)
        filter <- apply(counts, 1, function(row) length(row[row > 5]) >= 2)
        filtered <- counts[filter, ]
        genes <- rownames(filtered)
        
        # Create SeqExpressionSet object
        set <- newSeqExpressionSet(as.matrix(filtered),
                                   phenoData = data.frame(x, row.names = colnames(filtered)))
        
        # Perform upper-quartile normalization prior to RUVs
        set <- betweenLaneNormalization(set, which = "upper")
        
        # -----------------------------------------------------------------------------
        # Stage 2: Define Replicate Groups using makeGroups
        # -----------------------------------------------------------------------------
        
        differences <- makeGroups(x)
        
        # -----------------------------------------------------------------------------
        # Stage 3: Estimate Unwanted Variation Factors using RUVs
        # -----------------------------------------------------------------------------
        
        set3 <- RUVs(set, genes, k = 1, differences)
        pData(set3)
        
        # -----------------------------------------------------------------------------
        # Stage 4: Write Outputs and Generate Diagnostic Plots
        # -----------------------------------------------------------------------------
        
        # Save the estimated factors of unwanted variation
        write.csv(pData(set3), "ruvs_estimated_factors.csv", row.names = TRUE)
        
        # Save the normalized counts
        write.csv(normCounts(set3), "ruvs_normalized_counts.csv", row.names = TRUE)
        
        # Save the final SeqExpressionSet object
        saveRDS(set3, "ruvs_output_set.rds")
        
        # Generate diagnostic plots (RLE and PCA)
        pdf("ruvs_diagnostic_plots.pdf", width = 10, height = 8)
        par(mfrow = c(2, 2))
        
        colors <- brewer.pal(max(3, length(unique(x))), "Set2")
        color_mapping <- colors[x]
        
        plotRLE(set, outline = FALSE, main = "RLE Before RUVs", col = color_mapping)
        plotPCA(set, main = "PCA Before RUVs", col = color_mapping, cex = 1.2)
        
        plotRLE(set3, outline = FALSE, main = "RLE After RUVs", col = color_mapping)
        plotPCA(set3, main = "PCA After RUVs", col = color_mapping, cex = 1.2)
        
        dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_RUVSEQ_RUVS_REPLICATE_SAMPLES",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RUVSEQ_RUVS_REPLICATE_SAMPLES":',
        paste0('    RUVSeq: ', as.character(packageVersion('RUVSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ruvs_replicate_samples.csv versions.yml
    """
}

workflow BIOC_RUVSEQ_RUVS_REPLICATE_SAMPLES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.csv, sample_groups.csv ] ]

    main:
    BIOC_RUVSEQ_RUVS_REPLICATE_SAMPLES(ch_input)

    emit:
    tables   = BIOC_RUVSEQ_RUVS_REPLICATE_SAMPLES.out.tables
    plots    = BIOC_RUVSEQ_RUVS_REPLICATE_SAMPLES.out.plots
    objects  = BIOC_RUVSEQ_RUVS_REPLICATE_SAMPLES.out.objects
    versions = BIOC_RUVSEQ_RUVS_REPLICATE_SAMPLES.out.versions
}
