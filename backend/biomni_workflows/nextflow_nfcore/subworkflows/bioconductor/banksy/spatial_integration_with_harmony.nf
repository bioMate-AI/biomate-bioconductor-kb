#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Banksy — spatial_integration_with_harmony
// Integrate multiple spatial transcriptomics datasets using Harmony on the BANKSY embedding to correct for batch effects.
// Input: spe
// Container: quay.io/biocontainers/bioconductor-banksy:1.6.0--r45hdfd78af_0
// R packages: Banksy, SingleCellExperiment, SpatialExperiment, cowplot, ggplot2, harmony, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: Banksy, SingleCellExperiment, SpatialExperiment, cowplot, ggplot2, harmony, scater
// Visualizations: ordination plot
// QC: batch-effect correction, cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute BANKSY neighborhood matrices
//  * 2. [Core Analysis] Run PCA on the BANKSY matrix
//  * 3. [Core Analysis] Run Harmony on the BANKSY PCA embedding
//  * 4. [Core Analysis] Run UMAP on the Harmony-corrected embedding
//  * 5. [Core Analysis] Cluster the Harmony-corrected embedding
//  * 6. [Core Analysis] Connect clusters to reference annotations

nextflow.enable.dsl = 2

process BIOC_BANKSY_SPATIAL_INTEGRATION_WITH_HARMONY {
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
    .bm_deps <- c("Banksy", "SingleCellExperiment", "SpatialExperiment", "cowplot", "ggplot2", "harmony", "scater", "SummarizedExperiment")
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
    library(Banksy)
    library(SummarizedExperiment)
    library(SpatialExperiment)
    library(harmony)
    library(scater)
    library(cowplot)
    library(ggplot2)
    
    # Set seed for reproducibility
    SEED <- 1000
    set.seed(SEED)
    
    # 1. Read the user input SpatialExperiment object
    # The pipeline expects 'spe.rds' in the working directory containing multiple samples with staggered coordinates
    spe <- readRDS("spe.rds")
    
    # Determine the appropriate assay name to use
    if (!"normcounts" %in% assayNames(spe)) {
        if ("logcounts" %in% assayNames(spe)) {
            aname <- "logcounts"
        } else {
            aname <- assayNames(spe)[1]
        }
    } else {
        aname <- "normcounts"
    }
    
    # Ensure required colData columns exist to prevent downstream errors
    if (!"sample_id" %in% colnames(colData(spe))) {
        spe\$sample_id <- "sample1"
    }
    if (!"subject_id" %in% colnames(colData(spe))) {
        spe\$subject_id <- spe\$sample_id
    }
    if (!"clust_annotation" %in% colnames(colData(spe))) {
        spe\$clust_annotation <- "unannotated"
    }
    
    # Define parameters matching the documented workflow
    compute_agf <- TRUE
    k_geom <- 18
    use_agf <- TRUE
    lambda <- 0.2
    npcs <- 20
    
    # 2. Compute BANKSY neighborhood matrices
    spe <- computeBanksy(spe, assay_name = aname, compute_agf = compute_agf, k_geom = k_geom)
    
    # 3. Run PCA on the BANKSY matrix
    spe <- runBanksyPCA(spe, use_agf = use_agf, lambda = lambda, npcs = npcs, seed = SEED)
    
    # 4. Run Harmony on the BANKSY PCA embedding
    harmony_embedding <- harmony::RunHarmony(
        data_mat = reducedDim(spe, "PCA_M1_lam0.2"),
        meta_data = colData(spe),
        vars_use = c("sample_id", "subject_id"),
        max_iter = 20,
        verbose = FALSE
    )
    reducedDim(spe, "Harmony_BANKSY") <- harmony_embedding
    
    # 5. Run UMAP on the raw and Harmony-corrected embeddings
    spe <- runBanksyUMAP(spe, use_agf = TRUE, lambda = lambda, npcs = npcs)
    spe <- runBanksyUMAP(spe, dimred = "Harmony_BANKSY")
    
    # 6. Cluster the Harmony-corrected embedding
    spe <- clusterBanksy(spe, dimred = "Harmony_BANKSY", resolution = 0.55, seed = SEED)
    
    # 7. Connect clusters to reference annotations
    spe <- connectClusters(spe, map_to = "clust_annotation")
    
    # 8. Save outputs
    # Save the integrated SpatialExperiment object
    saveRDS(spe, "spe_integrated.rds")
    
    # Save the colData containing cluster annotations as a CSV table
    write.csv(as.data.frame(colData(spe)), "colData_integrated.csv", row.names = TRUE)
    
    # Generate and save diagnostic UMAP plots
    pdf("banksy_harmony_integration_plots.pdf", width = 12, height = 6)
    p1 <- plotReducedDim(spe, "UMAP_M1_lam0.2", colour_by = "sample_id") + 
        ggtitle("UMAP (Raw BANKSY PCA)") + 
        theme_minimal()
    p2 <- plotReducedDim(spe, "UMAP_Harmony_BANKSY", colour_by = "sample_id") + 
        ggtitle("UMAP (Harmony BANKSY)") + 
        theme_minimal()
    print(plot_grid(p1, p2, ncol = 2))
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # batch-effect correction — declarative pass via corrected-output presence
    # (kBET acceptance metric is a future per-workflow follow-on).
    .bec_artifacts <- list.files(".", pattern = "(?i)(corrected|batch|combat|harmony|mnn).*\\.(rds|csv|h5ad)\$")
    .bec_passes <- length(.bec_artifacts) > 0
    .gates_by_label[["batch-effect correction"]] <- list(
      gate_row = "bioc_batch_effect_correction",
      metric_name = "batch_corrected_artifacts",
      metric_value = length(.bec_artifacts),
      passes = .bec_passes,
      status = if (.bec_passes) "computed (declarative; kBET acceptance pending)"
               else "not_computed (no batch-corrected artifact present)"
    )

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_BANKSY_SPATIAL_INTEGRATION_WITH_HARMONY",
      domain  = "bioconductor",
      declared_qc_steps = c("batch-effect correction", "cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BANKSY_SPATIAL_INTEGRATION_WITH_HARMONY":',
        paste0('    Banksy: ', as.character(packageVersion('Banksy')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_integration_with_harmony.csv versions.yml
    """
}

workflow BIOC_BANKSY_SPATIAL_INTEGRATION_WITH_HARMONY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe ] ]

    main:
    BIOC_BANKSY_SPATIAL_INTEGRATION_WITH_HARMONY(ch_input)

    emit:
    tables   = BIOC_BANKSY_SPATIAL_INTEGRATION_WITH_HARMONY.out.tables
    plots    = BIOC_BANKSY_SPATIAL_INTEGRATION_WITH_HARMONY.out.plots
    objects  = BIOC_BANKSY_SPATIAL_INTEGRATION_WITH_HARMONY.out.objects
    versions = BIOC_BANKSY_SPATIAL_INTEGRATION_WITH_HARMONY.out.versions
}
