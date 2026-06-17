#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spotclean — standard_10x_visium_workflow
// Load raw 10x Visium Space Ranger output, perform decontamination, visualize results, and convert to a Seurat object.
// Input: raw_feature_bc_matrix/, tissue_positions_list.csv, tissue_lowres_image.png, scalefactors_json.json
// Container: quay.io/biocontainers/bioconductor-spotclean:1.12.0--r45hdfd78af_0
// R packages: Matrix, S4Vectors, ggplot2, knitr, SpatialExperiment, SpotClean
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPOTCLEAN_STANDARD_10X_VISIUM_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-spotclean:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("Matrix", "S4Vectors", "ggplot2", "knitr", "SpatialExperiment", "SpotClean")
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
    library(SpotClean)
    library(S4Vectors)
    library(ggplot2)
    library(Matrix)
    
    # Define spatial directory as the current working directory where the user files are located
    spatial_dir <- "."
    
    # --- Load raw count matrix ---
    mbrain_raw <- read10xRaw("raw_feature_bc_matrix")
    
    # --- Load slide metadata ---
    mbrain_slide_info <- read10xSlide(
      tissue_csv_file = file.path(spatial_dir, "tissue_positions_list.csv"),
      tissue_img_file = file.path(spatial_dir, "tissue_lowres_image.png"),
      scale_factor_file = file.path(spatial_dir, "scalefactors_json.json")
    )
    
    # --- Create slide object ---
    slide_obj <- createSlide(mbrain_raw, mbrain_slide_info)
    
    # --- Visualize raw slide, labels, and heatmaps ---
    p_slide <- visualizeSlide(slide_obj)
    ggplot2::ggsave("slide_visualization.pdf", plot = p_slide, width = 7, height = 7)
    
    p_label <- visualizeLabel(slide_obj, "tissue")
    ggplot2::ggsave("slide_tissue_label.pdf", plot = p_label, width = 7, height = 6)
    
    metadata(slide_obj)\$slide\$total_counts <- Matrix::colSums(mbrain_raw)
    p_heatmap_total <- visualizeHeatmap(slide_obj, "total_counts")
    ggplot2::ggsave("heatmap_total_counts_raw.pdf", plot = p_heatmap_total, width = 7, height = 6)
    
    p_heatmap_mbp_raw <- visualizeHeatmap(slide_obj, "Mbp")
    ggplot2::ggsave("heatmap_Mbp_raw.pdf", plot = p_heatmap_mbp_raw, width = 7, height = 6)
    
    # --- Decontaminate data ---
    decont_obj <- spotclean(slide_obj, maxit = 10, candidate_radius = 20)
    
    # --- Visualize decontaminated expression and contamination ---
    p_heatmap_mbp_decont <- visualizeHeatmap(decont_obj, "Mbp")
    ggplot2::ggsave("heatmap_Mbp_decont.pdf", plot = p_heatmap_mbp_decont, width = 7, height = 6)
    
    cont_summary <- summary(metadata(decont_obj)\$contamination_rate)
    write.csv(as.data.frame(t(as.matrix(cont_summary))), "contamination_rate_summary.csv", row.names = FALSE)
    
    # --- Calculate ambient RNA contamination score ---
    arc_val <- arcScore(slide_obj)
    writeLines(as.character(arc_val), "arc_score.txt")
    
    # --- Convert to Seurat object and save outputs ---
    seurat_obj <- convertToSeurat(decont_obj, image_dir = spatial_dir)
    
    saveRDS(decont_obj, "decont_obj.rds")
    saveRDS(seurat_obj, "seurat_decont_obj.rds")

    writeLines(c(
        '"BIOC_SPOTCLEAN_STANDARD_10X_VISIUM_WORKFLOW":',
        paste0('        spotclean: ', as.character(packageVersion("spotclean")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_10x_visium_workflow.csv versions.yml
    """
}

workflow BIOC_SPOTCLEAN_STANDARD_10X_VISIUM_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_feature_bc_matrix/, tissue_positions_list.csv, tissue_lowres_image.png, scalefactors_json.json ] ]

    main:
    BIOC_SPOTCLEAN_STANDARD_10X_VISIUM_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_SPOTCLEAN_STANDARD_10X_VISIUM_WORKFLOW.out.tables
    plots    = BIOC_SPOTCLEAN_STANDARD_10X_VISIUM_WORKFLOW.out.plots
    objects  = BIOC_SPOTCLEAN_STANDARD_10X_VISIUM_WORKFLOW.out.objects
    versions = BIOC_SPOTCLEAN_STANDARD_10X_VISIUM_WORKFLOW.out.versions
}
