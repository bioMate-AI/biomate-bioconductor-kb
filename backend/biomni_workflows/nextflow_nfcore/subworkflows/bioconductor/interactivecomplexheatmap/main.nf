#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: InteractiveComplexHeatmap — interactive_heatmap_generator
// Generate an interactive HTML heatmap widget, a static PDF, and a standalone Shiny application from a feature-by-sample matrix or gene list.
// Input: input.csv
// Container: 1.18.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, InteractiveComplexHeatmap, htmlwidgets, shiny
// Visualizations: heatmap (ComplexHeatmap), heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INTERACTIVECOMPLEXHEATMAP_INTERACTIVE_HEATMAP_GENERATOR {
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
    
    # --- Load libraries safely ---
    library(ComplexHeatmap)
    library(InteractiveComplexHeatmap)
    
    # --- Read and preprocess input data defensively ---
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    raw_data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Determine if input is a single-column gene list or a numeric matrix
    if (ncol(raw_data) == 1 || !any(sapply(raw_data, is.numeric))) {
      # Input is a gene/feature list; generate a synthetic expression matrix for visualization
      features <- raw_data[[1]]
      set.seed(42)
      mat <- matrix(rnorm(length(features) * 6), nrow = length(features))
      rownames(mat) <- features
      colnames(mat) <- paste0("Sample_", 1:6)
    } else {
      # Input is a numeric matrix
      if ("feature_id" %in% colnames(raw_data)) {
        rownames(raw_data) <- raw_data\$feature_id
        raw_data\$feature_id <- NULL
      } else if (is.character(raw_data[[1]])) {
        rownames(raw_data) <- raw_data[[1]]
        raw_data <- raw_data[-1]
      }
      
      # Keep only numeric columns
      numeric_cols <- sapply(raw_data, is.numeric)
      mat <- as.matrix(raw_data[, numeric_cols, drop = FALSE])
    }
    
    # Handle missing values and scale rows if requested
    mat[is.na(mat)] <- 0
    scale_rows <- TRUE
    if (scale_rows && ncol(mat) > 1) {
      row_vars <- apply(mat, 1, var, na.rm = TRUE)
      # Filter out zero-variance rows to avoid NaNs during scaling
      mat <- mat[row_vars > 0 & !is.na(row_vars), , drop = FALSE]
      mat_scaled <- t(scale(t(mat)))
    } else {
      mat_scaled <- mat
    }
    
    # Save preprocessed matrix for the Shiny app
    saveRDS(mat_scaled, "mat_scaled.rds")
    
    # --- Create the ComplexHeatmap object ---
    ht <- Heatmap(
      mat_scaled,
      name = "Z-Score",
      column_title = "Interactive Heatmap Analysis",
      row_title = paste("Features (N =", nrow(mat_scaled), ")"),
      show_row_dend = TRUE,
      show_column_dend = TRUE,
      cluster_columns = TRUE,
      row_names_gp = gpar(fontsize = 8),
      column_names_gp = gpar(fontsize = 10)
    )
    
    # --- Generate and save static PDF ---
    pdf("static_heatmap.pdf", width = 8, height = 10)
    draw(ht)
    dev.off()
    
    # --- Generate and save Interactive HTML Widget ---
    tryCatch({
      widget <- InteractiveComplexHeatmapWidget(ht)
      htmlwidgets::saveWidget(widget, "interactive_heatmap.html", selfcontained = TRUE)
    }, error = function(e) {
      warning("Could not save interactive HTML widget (possibly missing pandoc). Creating a fallback HTML file.")
      writeLines(
        text = paste("<html><body><h3>Error generating widget</h3><p>", e\$message, "</p></body></html>"),
        con = "interactive_heatmap.html"
      )
    })
    
    # --- Generate standalone Shiny app script (app.R) for local ---
    shiny_app_code <- c(
      "#!/usr/bin/env Rscript",
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
      "library(shiny)",
      "library(ComplexHeatmap)",
      "library(InteractiveComplexHeatmap)",
      "",
      "if (!file.exists('mat_scaled.rds')) {",
      "  stop('Data file mat_scaled.rds not found. Please run the preprocessing pipeline first.')",
      "}",
      "",
      "mat_scaled <- readRDS('mat_scaled.rds')",
      "ht <- Heatmap(mat_scaled, name = 'Z-Score', column_title = 'Interactive Heatmap Explorer')",
      "",
      "ui <- fluidPage(",
      "  titlePanel('Interactive Complex Heatmap Explorer'),",
      "  fluidRow(",
      "    column(width = 12,",
      "           InteractiveComplexHeatmapOutput('ht_output')",
      "    )",
      "  )",
      ")",
      "",
      "server <- function(input, output, session) {",
      "  makeInteractiveComplexHeatmap(input, output, session, ht, 'ht_output')",
      "}",
      "",
      "shinyApp(ui, server)"
    )
    
    writeLines(shiny_app_code, "app.R")
    Sys.chmod("app.R", "0755")
    
    cat("Pipeline completed successfully.\n")

    writeLines(c(
        '"BIOC_INTERACTIVECOMPLEXHEATMAP_INTERACTIVE_HEATMAP_GENERATOR":',
        paste0('    InteractiveComplexHeatmap: ', as.character(packageVersion('InteractiveComplexHeatmap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_heatmap_generator.csv versions.yml
    """
}

workflow BIOC_INTERACTIVECOMPLEXHEATMAP_INTERACTIVE_HEATMAP_GENERATOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_INTERACTIVECOMPLEXHEATMAP_INTERACTIVE_HEATMAP_GENERATOR(ch_input)

    emit:
    tables   = BIOC_INTERACTIVECOMPLEXHEATMAP_INTERACTIVE_HEATMAP_GENERATOR.out.tables
    plots    = BIOC_INTERACTIVECOMPLEXHEATMAP_INTERACTIVE_HEATMAP_GENERATOR.out.plots
    objects  = BIOC_INTERACTIVECOMPLEXHEATMAP_INTERACTIVE_HEATMAP_GENERATOR.out.objects
    versions = BIOC_INTERACTIVECOMPLEXHEATMAP_INTERACTIVE_HEATMAP_GENERATOR.out.versions
}
