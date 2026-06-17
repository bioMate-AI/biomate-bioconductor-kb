#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spaSim — spasim_spatial_simulation
// Simulate complex tumor-immune microenvironment spatial point patterns matching the dimensions of an input microscopy image, including mixed backgrounds, cluster
// Input: image.tif
// Container: 1.12.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EBImage, SingleCellExperiment, spaSim
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPASIM_SPASIM_SPATIAL_SIMULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("spaSim", "EBImage")
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
    library(spaSim)
    library(EBImage)
    
    # Set seed for reproducibility
    set.seed(42)
    
    # --- Read input microscopy image to extract spatial dimensions ---
    img_width <- 2000
    img_height <- 2000
    
    tryCatch({
      img <- EBImage::readImage("image.tif")
      img_dim <- dim(img)
      if (length(img_dim) >= 2) {
        img_width <- img_dim[1]
        img_height <- img_dim[2]
        message(paste("Successfully read image.tif. Dimensions:", img_width, "x", img_height))
      }
    }, error = function(e) {
      warning("Could not read image.tif or extract dimensions. Using default dimensions 2000x2000.")
    })
    
    # --- Simulate Background Cells (Hardcore Process) ---
    message("Simulating background cells...")
    bg <- simulate_background_cells(
      n_cells = 3000,
      width = img_width,
      height = img_height,
      method = "Hardcore",
      min_d = 15,
      oversampling_rate = 1.8,
      Cell.Type = "Others"
    )
    write.csv(bg, "simulated_background_cells.csv", row.names = FALSE)
    
    # --- Simulate Mixed Background ---
    message("Simulating mixed background...")
    mix_bg <- simulate_mixing(
      bg_sample = bg,
      idents = c("Tumour", "Immune", "Others"),
      props = c(0.15, 0.25, 0.60),
      plot_image = FALSE
    )
    write.csv(mix_bg, "simulated_mixed_background.csv", row.names = FALSE)
    
    # --- Simulate Clusters (Tumour and Immune Clusters) ---
    message("Simulating clusters...")
    cluster_properties <- list(
      C1 = list(
        name_of_cluster_cell = "Tumour",
        size = img_width * 0.15,
        shape = "Oval",
        centre_loc = data.frame(x = img_width * 0.3, y = img_height * 0.3),
        infiltration_types = c("Immune", "Others"),
        infiltration_proportions = c(0.1, 0.05)
      ),
      C2 = list(
        name_of_cluster_cell = "Immune",
        size = img_width * 0.2,
        shape = "Irregular",
        centre_loc = data.frame(x = img_width * 0.7, y = img_height * 0.7),
        infiltration_types = c("Tumour", "Others"),
        infiltration_proportions = c(0.05, 0.1)
      )
    )
    
    clusters <- simulate_clusters(
      bg_sample = mix_bg,
      n_clusters = 2,
      bg_type = "Others",
      cluster_properties = cluster_properties,
      plot_image = FALSE
    )
    write.csv(clusters, "simulated_clusters.csv", row.names = FALSE)
    
    # --- Simulate Immune Rings ---
    message("Simulating immune rings...")
    immune_ring_properties <- list(
      I1 = list(
        name_of_cluster_cell = "Tumour",
        size = img_width * 0.12,
        shape = "Circle",
        centre_loc = data.frame(x = img_width * 0.5, y = img_height * 0.5),
        infiltration_types = c("Immune", "Others"),
        infiltration_proportions = c(0.1, 0.1),
        name_of_ring_cell = "Immune",
        immune_ring_width = img_width * 0.04,
        immune_ring_infiltration_types = c("Others"),
        immune_ring_infiltration_proportions = c(0.1)
      )
    )
    
    rings <- simulate_immune_rings(
      bg_sample = bg,
      bg_type = "Others",
      n_ir = 1,
      ir_properties = immune_ring_properties,
      plot_image = FALSE
    )
    write.csv(rings, "simulated_immune_rings.csv", row.names = FALSE)
    
    # --- Simulate Double Rings ---
    message("Simulating double rings...")
    double_ring_properties <- list(
      D1 = list(
        name_of_cluster_cell = "Tumour",
        size = img_width * 0.1,
        shape = "Circle",
        centre_loc = data.frame(x = img_width * 0.4, y = img_height * 0.6),
        infiltration_types = c("Immune", "Others"),
        infiltration_proportions = c(0.1, 0.05),
        name_of_ring_cell = "Immune",
        immune_ring_width = img_width * 0.03,
        immune_ring_infiltration_types = c("Tumour", "Others"),
        immune_ring_infiltration_proportions = c(0.05, 0.1),
        name_of_double_ring_cell = "Others",
        double_ring_width = img_width * 0.03,
        double_ring_infiltration_types = c("Immune"),
        double_ring_infiltration_proportions = c(0.1)
      )
    )
    
    double_rings <- simulate_double_rings(
      bg_sample = bg,
      bg_type = "Others",
      n_dr = 1,
      dr_properties = double_ring_properties,
      plot_image = FALSE
    )
    write.csv(double_rings, "simulated_double_rings.csv", row.names = FALSE)
    
    # --- Simulate Vessels (Stripes) ---
    message("Simulating vessels...")
    properties_of_stripes <- list(
      S1 = list(
        number_of_stripes = 2,
        name_of_stripe_cell = "Immune",
        width_of_stripe = img_width * 0.02,
        infiltration_types = c("Others"),
        infiltration_proportions = c(0.1)
      )
    )
    
    vessels <- simulate_stripes(
      bg_sample = bg,
      n_stripe_type = 1,
      stripe_properties = properties_of_stripes,
      plot_image = FALSE
    )
    write.csv(vessels, "simulated_vessels.csv", row.names = FALSE)
    
    # --- Sequential Construction using TIS (Tissue Image Simulator) ---
    message("Running sequential tissue simulation (TIS)...")
    tis_cluster_properties <- list(
      C1 = list(
        name_of_cluster_cell = "Tumour",
        size = img_width * 0.12,
        shape = "Oval",
        centre_loc = data.frame(x = img_width * 0.25, y = img_height * 0.25),
        infiltration_types = c("Immune", "Others"),
        infiltration_proportions = c(0.2, 0.05)
      )
    )
    
    tis_ring_properties <- list(
      I1 = list(
        name_of_cluster_cell = "Tumour",
        size = img_width * 0.12,
        shape = "Circle",
        centre_loc = data.frame(x = img_width * 0.75, y = img_height * 0.75),
        infiltration_types = c("Immune", "Others"),
        infiltration_proportions = c(0.1, 0.1),
        name_of_ring_cell = "Immune",
        immune_ring_width = img_width * 0.04,
        immune_ring_infiltration_types = c("Others"),
        immune_ring_infiltration_proportions = c(0.1)
      )
    )
    
    simulated_sce <- TIS(
      bg_sample = NULL,
      n_cells = 4000,
      width = img_width,
      height = img_height,
      bg_method = "Hardcore",
      min_d = 12,
      oversampling_rate = 1.8,
      n_clusters = 1,
      properties_of_clusters = tis_cluster_properties,
      n_immune_rings = 1,
      properties_of_immune_rings = tis_ring_properties,
      plot_image = FALSE
    )
    saveRDS(simulated_sce, "simulated_tissue_sce.rds")
    
    # --- Simulate Multiple Images (Batch Simulation) ---
    message("Simulating batch variations...")
    # 1. Multiple background images with varying proportions
    idents_batch <- c("Tumour", "Immune", "Others")
    Tumour_prop <- c(0.1, 0.15, 0.2)
    Immune_prop <- c(0.1, 0.2, 0.3)
    Others_prop <- c(0.8, 0.65, 0.5)
    prop_list <- list(Tumour_prop, Immune_prop, Others_prop)
    
    bg_batch <- multiple_background_images(
      bg_sample = bg,
      idents = idents_batch,
      props = prop_list,
      plot_image = FALSE
    )
    saveRDS(bg_batch, "batch_background_images.rds")
    
    # 2. Multiple images with clusters of varying sizes
    range_of_size <- c(200, 400)
    cluster_batch <- multiple_images_with_clusters(
      bg_sample = bg,
      cluster_shape = 1,
      prop_infiltration = 0.1,
      cluster_size = range_of_size,
      cluster_loc_x = 0,
      cluster_loc_y = 0,
      plot_image = FALSE
    )
    saveRDS(cluster_batch, "batch_cluster_images.rds")
    
    # 3. Multiple images with immune rings of varying widths
    range_ring_width <- c(50, 100)
    ring_batch <- multiple_images_with_immune_rings(
      bg_sample = bg,
      cluster_size = 200,
      ring_shape = 1,
      prop_infiltration = 0,
      ring_width = range_ring_width,
      cluster_loc_x = 0,
      cluster_loc_y = 0,
      prop_ring_infiltration = 0.1,
      plot_image = FALSE
    )
    saveRDS(ring_batch, "batch_immune_ring_images.rds")
    
    # --- Generate Diagnostic Visualizations ---
    message("Generating diagnostic PDF plots...")
    pdf("simulated_spatial_patterns.pdf", width = 10, height = 10)
    
    # Plot Mixed Background
    simulate_mixing(
      bg_sample = bg,
      idents = c("Tumour", "Immune", "Others"),
      props = c(0.15, 0.25, 0.60),
      plot_image = TRUE,
      plot_colours = c("red", "darkgreen", "lightgray")
    )
    title("Simulated Mixed Background")
    
    # Plot Clusters
    simulate_clusters(
      bg_sample = mix_bg,
      n_clusters = 2,
      bg_type = "Others",
      cluster_properties = cluster_properties,
      plot_image = TRUE,
      plot_categories = c("Tumour", "Immune", "Others"),
      plot_colours = c("red", "darkgreen", "lightgray")
    )
    title("Simulated Clusters")
    
    # Plot Immune Rings
    simulate_immune_rings(
      bg_sample = bg,
      bg_type = "Others",
      n_ir = 1,
      ir_properties = immune_ring_properties,
      plot_image = TRUE,
      plot_categories = c("Tumour", "Immune", "Others"),
      plot_colours = c("red", "darkgreen", "lightgray")
    )
    title("Simulated Immune Rings")
    
    # Plot Double Rings
    simulate_double_rings(
      bg_sample = bg,
      bg_type = "Others",
      n_dr = 1,
      dr_properties = double_ring_properties,
      plot_image = TRUE,
      plot_categories = c("Tumour", "Immune", "Others"),
      plot_colours = c("red", "darkgreen", "lightgray")
    )
    title("Simulated Double Rings")
    
    # Plot Vessels
    simulate_stripes(
      bg_sample = bg,
      n_stripe_type = 1,
      stripe_properties = properties_of_stripes,
      plot_image = TRUE
    )
    title("Simulated Vessels (Stripes)")
    
    # Plot TIS Sequential Construction
    TIS(
      bg_sample = NULL,
      n_cells = 4000,
      width = img_width,
      height = img_height,
      bg_method = "Hardcore",
      min_d = 12,
      oversampling_rate = 1.8,
      n_clusters = 1,
      properties_of_clusters = tis_cluster_properties,
      n_immune_rings = 1,
      properties_of_immune_rings = tis_ring_properties,
      plot_image = TRUE,
      plot_categories = c("Tumour", "Immune", "Others"),
      plot_colours = c("red", "darkgreen", "lightgray")
    )
    title("TIS Sequential Construction")
    
    dev.off()
    
    message("Pipeline completed successfully. All outputs written to working directory.")

    writeLines(c(
        '"BIOC_SPASIM_SPASIM_SPATIAL_SIMULATION":',
        paste0('    spaSim: ', as.character(packageVersion('spaSim')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spasim_spatial_simulation.csv versions.yml
    """
}

workflow BIOC_SPASIM_SPASIM_SPATIAL_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SPASIM_SPASIM_SPATIAL_SIMULATION(ch_input)

    emit:
    tables   = BIOC_SPASIM_SPASIM_SPATIAL_SIMULATION.out.tables
    plots    = BIOC_SPASIM_SPASIM_SPATIAL_SIMULATION.out.plots
    objects  = BIOC_SPASIM_SPASIM_SPATIAL_SIMULATION.out.objects
    versions = BIOC_SPASIM_SPASIM_SPATIAL_SIMULATION.out.versions
}
