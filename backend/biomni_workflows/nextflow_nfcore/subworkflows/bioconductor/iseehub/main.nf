#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iSEEhub — iseehub_exploration_pipeline
// Initialize an interactive iSEEhub browser session customized with configurations derived from local input features.
// Input: input.csv
// Container: 1.12.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ExperimentHub, S4Vectors, iSEE, iSEEhub, shiny
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEEHUB_ISEEHUB_EXPLORATION_PIPELINE {
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
    
    # Stage 1: Load required libraries
    library(iSEEhub)
    library(ExperimentHub)
    library(S4Vectors)
    
    # Stage 2: Read and parse the input file defensively
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
      stop("Input file 'input.csv' not found in the working directory.")
    }
    
    df <- read.csv(input_file, check.names = FALSE)
    
    # Determine if input is a feature-by-sample matrix or a single-column list
    if (ncol(df) > 1) {
      if ("feature_id" %in% colnames(df)) {
        rownames(df) <- df\$feature_id
        df\$feature_id <- NULL
      } else {
        rownames(df) <- df[, 1]
        df <- df[, -1, drop = FALSE]
      }
      feature_ids <- rownames(df)
      message(sprintf("Successfully loaded matrix with %d features and %d samples.", length(feature_ids), ncol(df)))
    } else {
      feature_ids <- df[[1]]
      message(sprintf("Successfully loaded list of %d features.", length(feature_ids)))
    }
    
    # Stage 3: Query ExperimentHub for compatible datasets
    message("Connecting to ExperimentHub...")
    eh <- tryCatch({
      ExperimentHub()
    }, error = function(e) {
      warning("Could not connect to ExperimentHub. Creating a fallback empty hub representation.")
      NULL
    })
    
    if (!is.null(eh)) {
      message("Querying ExperimentHub for SummarizedExperiment resources...")
      eh_resources <- query(eh, "SummarizedExperiment")
      meta <- as.data.frame(mcols(eh_resources))
      
      # Save the metadata of the top 100 available datasets
      write.csv(head(meta, 100), "available_eh_datasets.csv", row.names = TRUE)
      message("Saved available ExperimentHub datasets to 'available_eh_datasets.csv'.")
    } else {
      write.csv(data.frame(Error = "ExperimentHub connection offline"), "available_eh_datasets.csv")
    }
    
    # Stage 4: Generate a custom iSEE configuration script based on input features
    # We select the top features to pre-configure a ComplexHeatmapPlot
    top_features <- head(feature_ids, 10)
    top_features_str <- paste(sprintf("'%s'", top_features), collapse = ", ")
    
    config_lines <- c(
      "# Custom iSEE configuration generated from input.csv",
      "library(iSEE)",
      "initial <- list(",
      "  ComplexHeatmapPlot(",
      "    PanelWidth = 12L,",
      "    Assay = 'logcounts',",
      sprintf("    RowData = c(%s)", top_features_str),
      "  )",
      ")"
    )
    writeLines(config_lines, "custom_isee_config.R")
    message("Created custom iSEE configuration in 'custom_isee_config.R'.")
    
    # Stage 5: Initialize and serialize the iSEEhub Shiny App
    if (!is.null(eh)) {
      message("Initializing iSEEhub application...")
      app <- iSEEhub(eh, runtime_install = FALSE)
      
      # Save the app object to an RDS file for deployment/execution
      saveRDS(app, "iseehub_app.rds")
      message("Saved iSEEhub Shiny app object to 'iseehub_app.rds'.")
      
      # Create an executable launch script
      launch_lines <- c(
        "#!/usr/bin/env Rscript",
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        "if (!requireNamespace('shiny', quietly = TRUE)) install.packages('shiny')",
        "app <- readRDS('iseehub_app.rds')",
        "message('Launching iSEEhub on http://127.0.0.1:1234')",
        "shiny::runApp(app, port = 1234)"
      )
      writeLines(launch_lines, "launch_app.R")
      Sys.chmod("launch_app.R", "0755")
      message("Created executable launch script 'launch_app.R'.")
    } else {
      message("Skipping app initialization due to missing ExperimentHub connection.")
      # Write dummy files to satisfy declared outputs
      saveRDS(NULL, "iseehub_app.rds")
      writeLines("# Connection failed", "launch_app.R")
    }

    writeLines(c(
        '"BIOC_ISEEHUB_ISEEHUB_EXPLORATION_PIPELINE":',
        paste0('    iSEEhub: ', as.character(packageVersion('iSEEhub')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseehub_exploration_pipeline.csv versions.yml
    """
}

workflow BIOC_ISEEHUB_ISEEHUB_EXPLORATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ISEEHUB_ISEEHUB_EXPLORATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_ISEEHUB_ISEEHUB_EXPLORATION_PIPELINE.out.tables
    plots    = BIOC_ISEEHUB_ISEEHUB_EXPLORATION_PIPELINE.out.plots
    objects  = BIOC_ISEEHUB_ISEEHUB_EXPLORATION_PIPELINE.out.objects
    versions = BIOC_ISEEHUB_ISEEHUB_EXPLORATION_PIPELINE.out.versions
}
