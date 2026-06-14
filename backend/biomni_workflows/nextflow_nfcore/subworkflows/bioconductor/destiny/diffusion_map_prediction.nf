#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: destiny — diffusion_map_prediction
// Project new cell samples into an existing reference diffusion map.
// Input: guo
// Container: quay.io/biocontainers/bioconductor-destiny:3.24.0--r45ha27e39d_0
// R packages: Biobase, destiny
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DESTINY_DIFFUSION_MAP_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-destiny:3.24.0--r45ha27e39d_0"

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
    .bm_deps <- c("Biobase", "destiny")
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
    library(destiny)
    library(Biobase)
    
    # Read the input 'guo' ExpressionSet from the working directory
    if (file.exists("guo")) {
      guo <- readRDS("guo")
    } else if (file.exists("guo.rds")) {
      guo <- readRDS("guo.rds")
    } else {
      stop("Required input file 'guo' or 'guo.rds' not found in the working directory.")
    }
    
    # --- Subset reference data (64-cell stage) and build reference ---
    ct64 <- guo[, guo \$ num_cells == 64 ]
    dm64 <- DiffusionMap (ct64)
    
    # --- Subset new query data (32-cell stage) ---
    ct32 <- guo[, guo \$ num_cells == 32 ]
    
    # --- Project query data into the reference map using dm_predict ---
    pred32 <- dm_predict (dm64, ct32)
    
    # --- Plot reference and projected data together and save to PDF ---
    pdf("diffusion_map_prediction_plot.pdf", width = 8, height = 8)
    plot (dm64, 1 : 2 , col = palette ()[[ 6 ]], new_dcs = pred32, col_new = palette ()[[ 4 ]])
    dev.off()
    
    # Save meaningful results to files
    saveRDS(dm64, "reference_diffusion_map_64.rds")
    saveRDS(pred32, "predicted_coordinates_32.rds")
    
    # Export predicted coordinates as a CSV table
    write.csv(as.data.frame(pred32), "predicted_coordinates_32.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_DESTINY_DIFFUSION_MAP_PREDICTION":',
        paste0('        destiny: ', as.character(packageVersion("destiny")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diffusion_map_prediction.csv versions.yml
    """
}

workflow BIOC_DESTINY_DIFFUSION_MAP_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ guo ] ]

    main:
    BIOC_DESTINY_DIFFUSION_MAP_PREDICTION(ch_input)

    emit:
    tables   = BIOC_DESTINY_DIFFUSION_MAP_PREDICTION.out.tables
    plots    = BIOC_DESTINY_DIFFUSION_MAP_PREDICTION.out.plots
    objects  = BIOC_DESTINY_DIFFUSION_MAP_PREDICTION.out.objects
    versions = BIOC_DESTINY_DIFFUSION_MAP_PREDICTION.out.versions
}
