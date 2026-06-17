#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: airpart — allelic_imbalance_analysis
// Identify genes with differential cell-type-specific allelic imbalance and partition cell types by their allelic ratios using single-cell allelic counts.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-airpart:1.18.0--r45hdfd78af_0
// R packages: airpart, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, airpart
// Visualizations: heatmap, dispersion plot, violin plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess the data to calculate allelic ratios and add pseudo-counts
//  * 2. [Core Analysis] Perform cell-level quality control
//  * 3. [Core Analysis] Perform gene-level quality control
//  * 4. [Core Analysis] Cluster genes by their allelic imbalance profiles
//  * 5. [Visualization & Output] Summarize allelic ratios and check for sufficient variation
//  * 6. [Core Analysis] Estimate over-dispersion to guide model selection
//  * 7. [Core Analysis] Partition cell types using fused lasso or Wilcoxon extension
//  * 8. [Core Analysis] Compute consensus partition if multiple iterations were run
//  * 9. [Core Analysis] Estimate posterior allelic ratios and test for dynamic allelic imbalance
//  * 10. [Visualization & Output] Extract results and visualize using forest, step, violin, or heatmap plots

nextflow.enable.dsl = 2

process BIOC_AIRPART_ALLELIC_IMBALANCE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("airpart", "SingleCellExperiment", "SummarizedExperiment")
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
        
         
        library(SummarizedExperiment)
       library(airpart)
        suppressPackageStartupMessages(library(SingleCellExperiment))
        
        # ==========================================
        # 0. Load and Validate User Input
        # ==========================================
        if (file.exists("sce.rds")) {
          sce <- readRDS("sce.rds")
        } else if (file.exists("sce")) {
          sce <- readRDS("sce")
        } else {
          stop("Input file 'sce' or 'sce.rds' not found in the working directory.")
        }
        
        if (!inherits(sce, "SingleCellExperiment")) {
          stop("Input object must be a SingleCellExperiment.")
        }
        if (!"x" %in% colnames(colData(sce))) {
          stop("colData(sce) must contain a column 'x' representing discrete cell types.")
        }
        if (!all(c("a1", "a2") %in% assayNames(sce))) {
          stop("sce must contain assays 'a1' and 'a2' representing allelic counts.")
        }
        
        # ==========================================
        # 1. Preprocess Data
        # ==========================================
        sce <- preprocess(sce)
        
        pdf("heatmap_preprocessed.pdf")
        print(makeHeatmap(sce))
        dev.off()
        
        # ==========================================
        # 2. Cell-level Quality Control
        # ==========================================
        cellQCmetrics <- cellQC(sce, mad_detected = 4)
        write.csv(as.data.frame(cellQCmetrics), "cell_qc_metrics.csv", row.names = TRUE)
        
        keep_cell <- (
          cellQCmetrics\$filter_sum |
            cellQCmetrics\$filter_detected |
            cellQCmetrics\$filter_spike
        )
        sce <- sce[, keep_cell]
        
        # ==========================================
        # 3. Gene-level Quality Control
        # ==========================================
        featureQCmetric <- featureQC(sce)
        write.csv(as.data.frame(featureQCmetric), "feature_qc_metrics.csv", row.names = TRUE)
        
        keep_feature <- (
          featureQCmetric\$filter_celltype &
            featureQCmetric\$filter_sd &
            featureQCmetric\$filter_spike
        )
        sce <- sce[keep_feature, ]
        
        # ==========================================
        # 4. Gene Clustering
        # ==========================================
        sce <- geneCluster(sce, G = 1:4)
        saveRDS(metadata(sce)\$geneCluster, "gene_cluster_metadata.rds")
        
        # ==========================================
        # 5. Summarize Allelic Ratios
        # ==========================================
        summary <- summaryAllelicRatio(sce)
        saveRDS(summary, "summary_allelic_ratio.rds")
        
        variation_check <- sapply(1:length(summary), function(i) {
          inst <- summary[[i]]
          inst_order <- inst[order(inst\$weighted.mean), ]
          max(diff(inst_order\$weighted.mean)) > 0.05
        })
        write.csv(
          data.frame(Cluster = seq_along(variation_check), SufficientVariation = variation_check),
          "variation_check.csv",
          row.names = FALSE
        )
        
        # ==========================================
        # 6. Estimate Over-dispersion
        # ==========================================
        pdf("dispersion_plot.pdf")
        print(estDisp(sce, genecluster = 1))
        dev.off()
        
        # ==========================================
        # 7. Partition Cell Types (Fused Lasso)
        # ==========================================
        sce_sub <- fusedLasso(sce,
          model = "binomial",
          genecluster = 1, ncores = 1,
          niter = 2
        )
        
        # ==========================================
        # 8. Consensus Partition
        # ==========================================
        sce_sub <- consensusPart(sce_sub)
        write.csv(as.data.frame(metadata(sce_sub)\$partition), "fused_lasso_partition.csv", row.names = FALSE)
        
        # Alternative: Wilcoxon Extension
        thrs <- 10^seq(from = -2, to = -0.4, by = 0.2)
        sce_sub_w <- wilcoxExt(sce, genecluster = 1, threshold = thrs)
        write.csv(as.data.frame(metadata(sce_sub_w)\$partition), "wilcox_partition.csv", row.names = FALSE)
        
        # ==========================================
        # 9. Estimate Posterior Allelic Ratios & Test
        # ==========================================
        sce_sub <- allelicRatio(sce_sub, DAItest = TRUE)
        
        pdf("forest_plot.pdf")
        print(makeForest(sce_sub, showtext = TRUE))
        dev.off()
        
        # ==========================================
        # 10. Extract Results and Visualize
        # ==========================================
        genepoi <- intersect(paste0("gene", seq_len(5)), rownames(sce_sub))
        if (length(genepoi) == 0) {
          genepoi <- head(rownames(sce_sub), min(5, nrow(sce_sub)))
        }
        
        ar <- extractResult(sce_sub)
        write.csv(as.data.frame(ar), "allelic_ratio_results.csv", row.names = TRUE)
        
        pdf("step_plot.pdf")
        print(makeStep(sce_sub[genepoi, ]))
        dev.off()
        
        s <- extractResult(sce_sub, "svalue")
        write.csv(as.data.frame(s), "svalues.csv", row.names = TRUE)
        
        s_check <- apply(s[genepoi, , drop = FALSE], 2, function(s) { s < 0.005 })
        write.csv(as.data.frame(s_check), "svalue_check_genepoi.csv", row.names = TRUE)
        
        adj.p <- mcols(sce_sub)\$adj.p.value
        names(adj.p) <- rownames(sce_sub)
        write.csv(
          data.frame(Gene = names(adj.p), adj.p.value = adj.p, Significant = adj.p < 0.05),
          "dynamic_ai_tests.csv",
          row.names = FALSE
        )
        
        pdf("violin_plot.pdf")
        print(makeViolin(sce_sub))
        dev.off()
        
        pdf("heatmap_grouped.pdf")
        print(makeHeatmap(sce_sub))
        dev.off()
        
        pdf("heatmap_ungrouped.pdf")
        print(makeHeatmap(sce_sub, order_by_group = FALSE))
        dev.off()
        
        # ==========================================
        # 11. Subset Analysis (Example II Workflow)
        # ==========================================
        sce_sub2 <- sce_sub[1:min(10, nrow(sce_sub)), ]
        sce_sub2 <- allelicRatio(sce_sub2)
        
        pdf("forest_plot_sub2.pdf")
        print(makeForest(sce_sub2))
        dev.off()
        
        ar2 <- extractResult(sce_sub2)
        write.csv(as.data.frame(ar2), "allelic_ratio_results_sub2.csv", row.names = TRUE)
        
        pdf("violin_plot_sub2.pdf")
        print(makeViolin(sce_sub2))
        dev.off()
        
        pdf("heatmap_grouped_sub2.pdf")
        print(makeHeatmap(sce_sub2))
        dev.off()
        
        pdf("heatmap_ungrouped_sub2.pdf")
        print(makeHeatmap(sce_sub2, order_by_group = FALSE))
        dev.off()

    writeLines(c(
        '"BIOC_AIRPART_ALLELIC_IMBALANCE_ANALYSIS":',
        paste0('    airpart: ', as.character(packageVersion('airpart')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_allelic_imbalance_analysis.csv versions.yml
    """
}

workflow BIOC_AIRPART_ALLELIC_IMBALANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_AIRPART_ALLELIC_IMBALANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_AIRPART_ALLELIC_IMBALANCE_ANALYSIS.out.tables
    plots    = BIOC_AIRPART_ALLELIC_IMBALANCE_ANALYSIS.out.plots
    objects  = BIOC_AIRPART_ALLELIC_IMBALANCE_ANALYSIS.out.objects
    versions = BIOC_AIRPART_ALLELIC_IMBALANCE_ANALYSIS.out.versions
}
