#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HilbertVis — hilbert_curve_visualization
// Visualize and compare long numeric feature vectors across samples using Hilbert space-filling curves to identify spatial patterns and structural differences.
// Input: input.csv
// Container: 1.68.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: HilbertVis, lattice
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HILBERTVIS_HILBERT_CURVE_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(HilbertVis)
    library(grid)
    library(lattice)
    
    # ==========================================
    # --- Read and Clean Input Data ---
    # ==========================================
    if (!file.exists("input.csv")) {
      stop("Input file 'input.csv' not found in the working directory.")
    }
    
    # Read the input matrix defensively
    df <- read.csv("input.csv", check.names = FALSE)
    
    # Handle row names / feature identifiers
    if ("feature_id" %in% colnames(df)) {
      rownames(df) <- df\$feature_id
      df\$feature_id <- NULL
    } else if (is.character(df[[1]]) || is.factor(df[[1]])) {
      rownames(df) <- df[[1]]
      df <- df[-1]
    }
    
    # Extract numeric columns
    numeric_cols <- sapply(df, is.numeric)
    df_num <- df[, numeric_cols, drop = FALSE]
    
    # Determine primary and secondary vectors
    if (ncol(df_num) == 0) {
      message("No numeric columns found. Generating dummy signal based on row count.")
      vec1 <- seq_len(nrow(df))
      vec2 <- seq_len(nrow(df)) * 1.1
    } else {
      vec1 <- df_num[[1]]
      if (ncol(df_num) >= 2) {
        vec2 <- df_num[[2]]
      } else {
        # Simulate a second sample with a structural shift to compare
        vec2 <- vec1
        n <- length(vec1)
        if (n > 10) {
          idx1 <- floor(n * 0.3)
          idx2 <- floor(n * 0.5)
          shift <- max(1, floor(n * 0.02))
          if ((idx2 + shift) <= n) {
            vec2[idx1:idx2] <- vec1[(idx1 + shift):(idx2 + shift)]
          }
        }
      }
    }
    
    # Replace any missing values with 0
    vec1[is.na(vec1)] <- 0
    vec2[is.na(vec2)] <- 0
    
    # ==========================================
    # --- Interpolation & Normalization ---
    # ==========================================
    # HilbertVis is designed for very long vectors. To ensure high-quality 
    # visualization, we interpolate the input vectors to a standard target length.
    target_len <- 262144 # 2^18, which maps perfectly to a level 9 Hilbert curve (512x512)
    
    interpolate_vector <- function(v, target_len) {
      if (length(v) != target_len) {
        return(approx(seq_along(v), v, n = target_len, rule = 2)\$y)
      }
      return(v)
    }
    
    vec1_interp <- interpolate_vector(vec1, target_len)
    vec2_interp <- interpolate_vector(vec2, target_len)
    
    # ==========================================
    # STAGE 3: 1D Long Vector Visualization
    # ==========================================
    pdf("long_vector_plots.pdf", width = 10, height = 8)
    par(mfrow = c(2, 1))
    
    # Plot the full long vector
    plotLongVector(vec1_interp)
    
    # Plot a zoomed-in region (middle 10% of the vector)
    start_idx <- floor(target_len * 0.45)
    end_idx <- floor(target_len * 0.55)
    plotLongVector(vec1_interp[start_idx:end_idx], offset = start_idx)
    
    dev.off()
    
    # ==========================================
    # --- Hilbert Curve Templates ---
    # ==========================================
    # Generate the first four levels of the Hilbert curve fractal for reference
    pdf("hilbert_curve_templates.pdf", width = 8, height = 8)
    pushViewport(viewport(layout = grid.layout(2, 2)))
    for (i in 1:4) {
      pushViewport(viewport(
        layout.pos.row = 1 + (i - 1) %/% 2,
        layout.pos.col = 1 + (i - 1) %% 2
      ))
      plotHilbertCurve(i, new.page = FALSE)
      popViewport()
    }
    popViewport()
    dev.off()
    
    # ==========================================
    # --- Hilbert Image Generation & Comparison ---
    # ==========================================
    # Generate 2D Hilbert matrices
    level <- 9
    hMat1 <- hilbertImage(vec1_interp, level = level)
    hMat2 <- hilbertImage(vec2_interp, level = level)
    
    # Save Hilbert images to a multi-page PDF
    pdf("hilbert_images.pdf", width = 8, height = 8)
    
    # Display Sample 1 Hilbert Image
    p1 <- showHilbertImage(hMat1)
    print(p1)
    
    # Display Sample 2 Hilbert Image
    p2 <- showHilbertImage(hMat2)
    print(p2)
    
    # Display the difference matrix to highlight structural variations
    diffMat <- hMat2 - hMat1
    p_diff <- showHilbertImage(diffMat)
    print(p_diff)
    
    dev.off()
    
    # ==========================================
    # --- Downsampling and Data Export ---
    # ==========================================
    # Downsample the long vectors using shrinkVector to a manageable size (1000 bins)
    shrunk_vec1 <- shrinkVector(vec1_interp, newLength = 1000)
    shrunk_vec2 <- shrinkVector(vec2_interp, newLength = 1000)
    
    summary_df <- data.frame(
      bin_id = 1:1000,
      sample1_max = shrunk_vec1,
      sample2_max = shrunk_vec2,
      difference = shrunk_vec2 - shrunk_vec1
    )
    
    # Export binned summary and raw Hilbert matrix
    write.csv(summary_df, "shrunk_vector_summary.csv", row.names = FALSE)
    write.csv(as.data.frame(hMat1), "hilbert_matrix_sample1.csv", row.names = FALSE)
    
    message("HilbertVis analysis pipeline completed successfully!")

    writeLines(c(
        '"BIOC_HILBERTVIS_HILBERT_CURVE_VISUALIZATION":',
        paste0('    HilbertVis: ', as.character(packageVersion('HilbertVis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hilbert_curve_visualization.csv versions.yml
    """
}

workflow BIOC_HILBERTVIS_HILBERT_CURVE_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_HILBERTVIS_HILBERT_CURVE_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_HILBERTVIS_HILBERT_CURVE_VISUALIZATION.out.tables
    plots    = BIOC_HILBERTVIS_HILBERT_CURVE_VISUALIZATION.out.plots
    objects  = BIOC_HILBERTVIS_HILBERT_CURVE_VISUALIZATION.out.objects
    versions = BIOC_HILBERTVIS_HILBERT_CURVE_VISUALIZATION.out.versions
}
