#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: splots — splots_plate_visualization
// Visualize high-throughput microtitre plate assay data by mapping sample expression metrics to plate layouts and generating spatial heatmaps for quality control.
// Input: counts.csv, coldata.csv
// Container: 1.76.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: splots
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPLOTS_SPLOTS_PLATE_VISUALIZATION {
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
    .bm_deps <- c("splots")
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
    library(splots)
    
    # --- Load and preprocess input data ---
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Compute a per-sample summary metric (e.g., total sum of counts as a proxy for well intensity/viability)
    well_intensities <- colSums(counts)
    
    # Align coldata with the counts columns
    common_samples <- intersect(coldata\$sample, names(well_intensities))
    if (length(common_samples) == 0) {
      # Fallback mapping if names do not match exactly
      common_samples <- coldata\$sample[1:min(nrow(coldata), ncol(counts))]
      names(well_intensities) <- common_samples
    }
    
    coldata <- coldata[coldata\$sample %in% common_samples, ]
    coldata\$intensity <- well_intensities[coldata\$sample]
    
    # --- Map samples to microtitre plate layout (96-well format: ---
    nx <- 12
    ny <- 8
    wells_per_plate <- nx * ny
    num_samples <- nrow(coldata)
    
    # Sequentially assign samples to plates, rows, and columns
    coldata\$plate <- paste0("Plate_", ((seq_len(num_samples) - 1) %/% wells_per_plate) + 1)
    coldata\$well_idx <- ((seq_len(num_samples) - 1) %% wells_per_plate) + 1
    coldata\$row <- ((coldata\$well_idx - 1) %/% nx) + 1
    coldata\$col <- ((coldata\$well_idx - 1) %% nx) + 1
    
    # --- Format data structure for splots::plotScreen ---
    plates <- unique(coldata\$plate)
    xl <- lapply(plates, function(pl) {
      plate_data <- coldata[coldata\$plate == pl, ]
      rv <- rep(NA_real_, wells_per_plate)
      idx <- (plate_data\$row - 1) * nx + plate_data\$col
      rv[idx] <- plate_data\$intensity
      return(rv)
    })
    names(xl) <- plates
    
    # --- Generate spatial plate visualization ---
    pdf("plate_screen_visualization.pdf", width = 10, height = 8)
    tryCatch({
      splots::plotScreen(
        xl,
        nx = nx,
        ny = ny,
        ncol = ceiling(sqrt(length(xl))),
        fill = c("white", "#00008B"),
        main = "Microtitre Plate Screen QC",
        legend.label = "Total Counts",
        zrange = c(0, max(unlist(xl), na.rm = TRUE))
      )
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Error generating plotScreen:", e\$message), cex = 0.8)
    })
    dev.off()
    
    # --- Save mapped layout metadata ---
    write.csv(coldata, "plate_layout_metadata.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SPLOTS_SPLOTS_PLATE_VISUALIZATION":',
        paste0('    splots: ', as.character(packageVersion('splots')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splots_plate_visualization.csv versions.yml
    """
}

workflow BIOC_SPLOTS_SPLOTS_PLATE_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SPLOTS_SPLOTS_PLATE_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SPLOTS_SPLOTS_PLATE_VISUALIZATION.out.tables
    plots    = BIOC_SPLOTS_SPLOTS_PLATE_VISUALIZATION.out.plots
    objects  = BIOC_SPLOTS_SPLOTS_PLATE_VISUALIZATION.out.objects
    versions = BIOC_SPLOTS_SPLOTS_PLATE_VISUALIZATION.out.versions
}
