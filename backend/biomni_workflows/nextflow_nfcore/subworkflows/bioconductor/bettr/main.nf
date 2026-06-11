#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bettr — bettr_genomic_benchmark
// Benchmark genomic regions or peak-calling methods by extracting performance metrics from a BED file and metadata, then visualizing and ranking them using bettr.
// Input: regions.bed, coldata.csv
// Container: 1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, SummarizedExperiment, bettr, dplyr, rtracklayer, tibble
// Visualizations: heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BETTR_BETTR_GENOMIC_BENCHMARK {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    library(bettr)
    library(rtracklayer)
    library(dplyr)
    library(tibble)
    
    # ==========================================
    # --- Input Processing & Feature Extraction ---
    # ==========================================
    
    message("Step 1: Importing genomic intervals from regions.bed...")
    gr <- rtracklayer::import("regions.bed")
    df_bed <- as.data.frame(gr)
    
    # Ensure score column exists and is numeric
    if (!"score" %in% colnames(df_bed) || all(is.na(df_bed\$score))) {
      message("Warning: 'score' column missing or empty in BED. Generating default scores.")
      df_bed\$score <- seq_len(nrow(df_bed))
    } else {
      df_bed\$score <- as.numeric(df_bed\$score)
    }
    
    # Determine the column to use as the Method identifier
    # If 'name' has multiple unique values, we treat it as the Method/Algorithm name.
    # Otherwise, we fallback to using chromosomes (seqnames) as the comparison groups.
    if ("name" %in% colnames(df_bed) && length(unique(df_bed\$name)) > 1) {
      id_col <- "name"
    } else {
      message("Using chromosome (seqnames) as the comparison group (Method).")
      df_bed\$name <- as.character(df_bed\$seqnames)
      id_col <- "name"
    }
    
    message("Step 2: Calculating benchmark metrics per method...")
    # Compute multiple metrics to evaluate each method
    benchmark_df <- df_bed %>%
      group_by(Method = !!sym(id_col)) %>%
      summarize(
        mean_score = mean(score, na.rm = TRUE),
        max_score = max(score, na.rm = TRUE),
        total_width = sum(width, na.rm = TRUE),
        mean_width = mean(width, na.rm = TRUE),
        num_regions = n(),
        .groups = "drop"
      )
    
    # Read optional metadata if available
    if (file.exists("coldata.csv")) {
      message("Step 3: Integrating metadata from coldata.csv...")
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
      if (!"Method" %in% colnames(coldata)) {
        colnames(coldata)[1] <- "Method"
      }
      idInfo <- coldata[coldata\$Method %in% benchmark_df\$Method, , drop = FALSE]
      if (nrow(idInfo) == 0) {
        idInfo <- data.frame(Method = benchmark_df\$Method, Type = "DefaultType")
      }
    } else {
      idInfo <- data.frame(Method = benchmark_df\$Method, Type = "DefaultType")
    }
    
    # Define metric metadata (grouping metrics into classes)
    metricInfo <- data.frame(
      Metric = c("mean_score", "max_score", "total_width", "mean_width", "num_regions"),
      Class = c("Score", "Score", "Size", "Size", "Count"),
      stringsAsFactors = FALSE
    )
    
    # ==========================================
    # --- Normalization & Transformation Setup ---
    # ==========================================
    
    message("Step 4: Setting up metric transformations...")
    # For 'mean_width' and 'num_regions', smaller values are typically preferred (flip = TRUE).
    # For scores and total width, larger values are preferred (flip = FALSE).
    # All metrics are scaled to [0, 1] to ensure comparability.
    initialTransforms <- list(
      mean_score  = list(flip = FALSE, transform = "[0,1]"),
      max_score   = list(flip = FALSE, transform = "[0,1]"),
      total_width = list(flip = FALSE, transform = "[0,1]"),
      mean_width  = list(flip = TRUE,  transform = "[0,1]"),
      num_regions = list(flip = TRUE,  transform = "[0,1]")
    )
    
    # ==========================================
    # --- Assemble SummarizedExperiment ---
    # ==========================================
    
    message("Step 5: Assembling SummarizedExperiment...")
    se <- assembleSE(
      df = as.data.frame(benchmark_df),
      idCol = "Method",
      metricInfo = metricInfo,
      idInfo = idInfo,
      initialTransforms = initialTransforms
    )
    
    # ==========================================
    # --- Programmatic Preparation & Scoring ---
    # ==========================================
    
    message("Step 6: Preparing data and calculating aggregated scores...")
    prepData <- bettrGetReady(
      bettrSE = se,
      idCol = "Method",
      scoreMethod = "weighted mean",
      metricGrouping = "Class",
      metricCollapseGroup = TRUE
    )
    
    # Save final scores and rankings
    write.csv(prepData\$scoredata, "benchmark_scores.csv", row.names = FALSE)
    message("Saved aggregated scores to 'benchmark_scores.csv'.")
    
    # ==========================================
    # --- Visualization & Serialization ---
    # ==========================================
    
    message("Step 7: Generating diagnostic plots...")
    
    # 1. Heatmap
    pdf("heatmap.pdf", width = 10, height = 8)
    hm <- makeHeatmap(bettrList = prepData)
    if (inherits(hm, "Heatmap")) {
      ComplexHeatmap::draw(hm)
    } else {
      print(hm)
    }
    dev.off()
    message("Saved heatmap to 'heatmap.pdf'.")
    
    # 2. Polar and Parallel Coordinate Plots
    pdf("polar_plots.pdf", width = 8, height = 8)
    tryCatch({
      print(makePolarPlot(bettrList = prepData))
    }, error = function(e) {
      message("Warning: Could not generate Polar Plot: ", e\$message)
    })
    
    tryCatch({
      print(makeBarPolarPlot(bettrList = prepData))
    }, error = function(e) {
      message("Warning: Could not generate Bar Polar Plot: ", e\$message)
    })
    
    tryCatch({
      print(makeParCoordPlot(bettrList = prepData))
    }, error = function(e) {
      message("Warning: Could not generate Parallel Coordinate Plot: ", e\$message)
    })
    dev.off()
    message("Saved polar and coordinate plots to 'polar_plots.pdf'.")
    
    # 3. Export to JSON for web/server mode compatibility
    message("Step 8: Exporting benchmark to JSON...")
    bettrToJSON(se, file = "bettr_benchmark.json")
    message("Saved JSON configuration to 'bettr_benchmark.json'.")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_BETTR_BETTR_GENOMIC_BENCHMARK":',
        paste0('    bettr: ', as.character(packageVersion('bettr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bettr_genomic_benchmark.csv versions.yml
    """
}

workflow BIOC_BETTR_BETTR_GENOMIC_BENCHMARK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BETTR_BETTR_GENOMIC_BENCHMARK(ch_input)

    emit:
    tables   = BIOC_BETTR_BETTR_GENOMIC_BENCHMARK.out.tables
    plots    = BIOC_BETTR_BETTR_GENOMIC_BENCHMARK.out.plots
    objects  = BIOC_BETTR_BETTR_GENOMIC_BENCHMARK.out.objects
    versions = BIOC_BETTR_BETTR_GENOMIC_BENCHMARK.out.versions
}
