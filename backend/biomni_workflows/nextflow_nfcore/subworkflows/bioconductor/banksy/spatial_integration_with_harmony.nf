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
