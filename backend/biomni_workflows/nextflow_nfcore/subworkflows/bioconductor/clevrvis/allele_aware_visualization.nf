#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clevRvis — allele_aware_visualization
// Generate an allele-aware visualization (plaice plot) showing clonal evolution alongside bi-allelic events and remaining healthy alleles over time.
// Input: fracTable, parents, timepoints
// Container: quay.io/biocontainers/bioconductor-clevrvis:1.10.0--r45hdfd78af_0
// R packages: clevRvis
// Bioconductor: 3.20 | R: 4.4
// Requires: clevRvis, htmlwidgets
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create seaObject with timepoint interpolation or therapy effect estimation
//  * 2. [Visualization & Output] Generate plaice plots with optional annotations and custom clone coloring to represent bi-allelic events

nextflow.enable.dsl = 2

process BIOC_CLEVRVIS_ALLELE_AWARE_VISUALIZATION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("clevRvis")
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
        library(clevRvis)
        
        # Helper function to find and read matrix from working directory
        find_and_read_matrix <- function(base_name) {
          extensions <- c("", ".csv", ".tsv", ".txt", ".rds")
          for (ext in extensions) {
            path <- paste0(base_name, ext)
            if (file.exists(path)) {
              message("Reading matrix from: ", path)
              if (ext == ".rds") {
                return(as.matrix(readRDS(path)))
              } else {
                sep <- if (ext == ".tsv") "\t" else ","
                df <- read.table(path, header = FALSE, sep = sep, stringsAsFactors = FALSE)
                # Check if first row is header
                if (any(is.na(suppressWarnings(as.numeric(df[1, ]))))) {
                  df <- read.table(path, header = TRUE, sep = sep, stringsAsFactors = FALSE)
                }
                # Check if first col is row names
                if (any(is.na(suppressWarnings(as.numeric(df[, 1]))))) {
                  df <- df[, -1, drop = FALSE]
                }
                return(as.matrix(df))
              }
            }
          }
          stop(paste("Required input file for", base_name, "not found in the working directory."))
        }
        
        # Helper function to find and read vector from working directory
        find_and_read_vector <- function(base_name, is_integer = FALSE) {
          extensions <- c("", ".csv", ".tsv", ".txt", ".rds")
          for (ext in extensions) {
            path <- paste0(base_name, ext)
            if (file.exists(path)) {
              message("Reading vector from: ", path)
              if (ext == ".rds") {
                val <- readRDS(path)
                return(if (is_integer) as.integer(val) else as.numeric(val))
              } else {
                sep <- if (ext == ".tsv") "\t" else ","
                df <- read.table(path, header = FALSE, sep = sep, stringsAsFactors = FALSE)
                if (any(is.na(suppressWarnings(as.numeric(df[1, 1]))))) {
                  df <- read.table(path, header = TRUE, sep = sep, stringsAsFactors = FALSE)
                }
                val <- unlist(df, use.names = FALSE)
                return(if (is_integer) as.integer(val) else as.numeric(val))
              }
            }
          }
          stop(paste("Required input file for", base_name, "not found in the working directory."))
        }
        
        # Read user inputs
        fracTable <- find_and_read_matrix("fracTable")
        parents <- find_and_read_vector("parents", is_integer = TRUE)
        timepoints <- find_and_read_vector("timepoints", is_integer = FALSE)
        
        message("Successfully loaded input files:")
        message("  - fracTable dimensions: ", paste(dim(fracTable), collapse = "x"))
        message("  - parents length: ", length(parents))
        message("  - timepoints length: ", length(timepoints))
        
        # Dynamically define therapyEffect based on input timepoints
        if (length(timepoints) >= 2) {
          therapyEffect <- c(timepoints[1], timepoints[2])
        } else {
          therapyEffect <- timepoints[1]
        }
        
        # Dynamically define clonesToFill based on the number of clones
        clonesToFill <- rep(0, nrow(fracTable))
        if (length(clonesToFill) >= 6) {
          clonesToFill[3] <- 1
          clonesToFill[6] <- 6
        } else if (length(clonesToFill) >= 3) {
          clonesToFill[3] <- 1
        }
        
        # Dynamically scale annotations based on timepoints range
        tp_range <- range(timepoints)
        x_annots <- tp_range[1] + c(0.24, 0.55) * diff(tp_range)
        annotsTable <- data.frame(x = x_annots, y = c(-40,-5), 
                                  col = c('black', 'white'), 
                                  lab = c('TP53', 'UBA1'))
        
        # 1. Create seaObjects with timepoint interpolation and therapy effect estimation
        seaObject_tp <- createSeaObject(fracTable, parents, timepoints,
                                        timepointInterpolation = TRUE)
        
        seaObject_te <- createSeaObject(fracTable, parents, timepoints,
                                        timepointInterpolation = TRUE,
                                        therapyEffect = therapyEffect)
        
        # Save constructed seaObjects
        saveRDS(seaObject_tp, "seaObject_tp.rds")
        saveRDS(seaObject_te, "seaObject_te.rds")
        message("Saved seaObjects to RDS files.")
        
        # 2. Generate plaice plots (interactive widgets)
        p1 <- plaicePlot(seaObject_tp, showLegend = TRUE,  vlines = timepoints,
                         vlab = timepoints, vlabSize = 4, ylab = TRUE, 
                         separateIndependentClones = TRUE)
        
        p2 <- plaicePlot(seaObject_tp, showLegend = TRUE,  vlines = timepoints,
                         vlab = timepoints, vlabSize = 4, ylab = TRUE, 
                         separateIndependentClones = TRUE, clonesToFill = clonesToFill,
                         annotations = annotsTable)
        
        p3 <- plaicePlot(seaObject_te, showLegend = TRUE,  vlines = timepoints,
                         vlab = timepoints, vlabSize = 4, ylab = TRUE, 
                         separateIndependentClones = TRUE)
        
        # Save interactive HTML widgets if htmlwidgets is available
        if (requireNamespace("htmlwidgets", quietly = TRUE)) {
          tryCatch({
            htmlwidgets::saveWidget(p1, "plaice_plot_healthy.html", selfcontained = TRUE)
            htmlwidgets::saveWidget(p2, "plaice_plot_biallelic.html", selfcontained = TRUE)
            htmlwidgets::saveWidget(p3, "plaice_plot_therapy.html", selfcontained = TRUE)
            message("Saved interactive HTML widgets.")
          }, error = function(e) {
            warning("Failed to save interactive HTML widgets: ", e\$message)
          })
        }
        
        # Save static PDF versions of the plots
        pdf("plaice_plots_static.pdf", width = 10, height = 8)
        tryCatch({
          print(plaicePlot(seaObject_tp, showLegend = TRUE,  vlines = timepoints,
                      vlab = timepoints, vlabSize = 4, ylab = TRUE, 
                      separateIndependentClones = TRUE, interactivePlot = FALSE))
          
          print(plaicePlot(seaObject_tp, showLegend = TRUE,  vlines = timepoints,
                      vlab = timepoints, vlabSize = 4, ylab = TRUE, 
                      separateIndependentClones = TRUE, clonesToFill = clonesToFill,
                      annotations = annotsTable, interactivePlot = FALSE))
          
          print(plaicePlot(seaObject_te, showLegend = TRUE,  vlines = timepoints,
                      vlab = timepoints, vlabSize = 4, ylab = TRUE, 
                      separateIndependentClones = TRUE, interactivePlot = FALSE))
          message("Saved static PDF plots.")
        }, error = function(e) {
          warning("Failed to save static PDF plots: ", e\$message)
        })
        dev.off()
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CLEVRVIS_ALLELE_AWARE_VISUALIZATION":',
        paste0('    clevRvis: ', as.character(packageVersion('clevRvis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_allele_aware_visualization.csv versions.yml
    """
}

workflow BIOC_CLEVRVIS_ALLELE_AWARE_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fracTable, parents, timepoints ] ]

    main:
    BIOC_CLEVRVIS_ALLELE_AWARE_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_CLEVRVIS_ALLELE_AWARE_VISUALIZATION.out.tables
    plots    = BIOC_CLEVRVIS_ALLELE_AWARE_VISUALIZATION.out.plots
    objects  = BIOC_CLEVRVIS_ALLELE_AWARE_VISUALIZATION.out.objects
    versions = BIOC_CLEVRVIS_ALLELE_AWARE_VISUALIZATION.out.versions
}
