#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clevRvis — standard_clonal_visualization
// Create a seaObject from clone fractions and parental relations, optionally interpolate timepoints or estimate therapy effects, and visualize using shark, dolphi
// Input: fracTable, parents, timepoints
// Container: quay.io/biocontainers/bioconductor-clevrvis:1.10.0--r45hdfd78af_0
// R packages: clevRvis, htmlwidgets, knitr
// Bioconductor: 3.20 | R: 4.4
// Requires: clevRvis, htmlwidgets
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create seaObject with or without timepoint interpolation and therapy effect estimation
//  * 2. [Visualization & Output] Generate basic or extended shark plots
//  * 3. [Visualization & Output] Generate detailed dolphin plots
//  * 4. [Visualization & Output] Generate linked interactive combined plots

nextflow.enable.dsl = 2

process BIOC_CLEVRVIS_STANDARD_CLONAL_VISUALIZATION {
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
    .bm_deps <- c("clevRvis", "htmlwidgets", "knitr")
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
    library(htmlwidgets)
    
    # Helper function to read input matrix
    read_input_matrix <- function(filename, default_val = NULL) {
      if (file.exists(filename)) {
        ext <- tools::file_ext(filename)
        if (ext == "rds") {
          return(readRDS(filename))
        } else if (ext == "csv") {
          return(as.matrix(read.csv(filename, header = FALSE)))
        } else {
          return(as.matrix(read.table(filename)))
        }
      }
      return(default_val)
    }
    
    # Helper function to read input vector
    read_input_vector <- function(filename, default_val = NULL) {
      if (file.exists(filename)) {
        ext <- tools::file_ext(filename)
        if (ext == "rds") {
          return(readRDS(filename))
        } else if (ext == "csv") {
          val <- read.csv(filename, header = FALSE)
          if (nrow(val) == 1) {
            return(as.numeric(val[1, ]))
          } else {
            return(as.numeric(val[, 1]))
          }
        } else {
          return(scan(filename, quiet = TRUE))
        }
      }
      return(default_val)
    }
    
    # Helper function to safely save PDF plots
    save_pdf_plot <- function(filename, plot_expr) {
      tryCatch({
        pdf(filename, width = 10, height = 8)
        print(plot_expr)
        dev.off()
        message("Successfully saved plot: ", filename)
      }, error = function(e) {
        message("Failed to save plot ", filename, ": ", e\$message)
        if (names(dev.cur()) != "null device") dev.off()
      })
    }
    
    # Helper function to safely save HTML widgets
    save_widget_plot <- function(filename, widget_obj) {
      tryCatch({
        htmlwidgets::saveWidget(widget_obj, filename, selfcontained = TRUE)
        message("Successfully saved widget: ", filename)
      }, error = function(e) {
        message("Failed to save widget ", filename, ": ", e\$message)
      })
    }
    
    # -----------------------------------------------------------------------------
    # 1. Read User Inputs
    # -----------------------------------------------------------------------------
    fracTable <- read_input_matrix("fracTable.csv")
    if (is.null(fracTable)) fracTable <- read_input_matrix("fracTable.rds")
    if (is.null(fracTable)) fracTable <- read_input_matrix("fracTable.txt")
    
    parents <- read_input_vector("parents.csv")
    if (is.null(parents)) parents <- read_input_vector("parents.rds")
    if (is.null(parents)) parents <- read_input_vector("parents.txt")
    
    timepoints <- read_input_vector("timepoints.csv")
    if (is.null(timepoints)) timepoints <- read_input_vector("timepoints.rds")
    if (is.null(timepoints)) timepoints <- read_input_vector("timepoints.txt")
    
    if (is.null(fracTable) || is.null(parents) || is.null(timepoints)) {
      stop("Error: Missing required input files (fracTable, parents, timepoints) in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Dynamic Parameter Setup
    # -----------------------------------------------------------------------------
    num_clones <- nrow(fracTable)
    
    # Dynamically determine therapy effect timepoints based on input data
    te_val <- c(50, 100)
    if (length(timepoints) >= 2) {
      if (!all(c(50, 100) %in% timepoints)) {
        te_val <- c(timepoints[length(timepoints) - 1], timepoints[length(timepoints)])
      }
    } else {
      te_val <- NULL
    }
    
    # Dynamically generate colors matching the number of clones
    colors_val <- rainbow(num_clones)
    
    # Dynamically construct clonesToFill vector matching the number of clones
    clonesToFill_val <- rep(0, num_clones)
    if (num_clones >= 6) {
      clonesToFill_val[3] <- 1
      clonesToFill_val[6] <- 6
    } else if (num_clones >= 3) {
      clonesToFill_val[3] <- 1
    }
    
    # Dynamically construct annotations within the range of timepoints
    min_t <- min(timepoints)
    max_t <- max(timepoints)
    mid_t1 <- min_t + (max_t - min_t) * 0.5
    mid_t2 <- min_t + (max_t - min_t) * 0.75
    annotsTable <- data.frame(
      x = c(mid_t1, mid_t2),
      y = c(15, 50),
      col = c('black', 'white'),
      lab = c('Annotation clone 5', 'Annotation clone 2')
    )
    
    # -----------------------------------------------------------------------------
    # 3. Create seaObjects
    # -----------------------------------------------------------------------------
    seaObject <- createSeaObject(fracTable, parents, timepoints,
                                timepointInterpolation = FALSE)
    saveRDS(seaObject, "seaObject.rds")
    
    seaObject_tp <- createSeaObject(fracTable, parents, timepoints,
                                    timepointInterpolation = TRUE)
    saveRDS(seaObject_tp, "seaObject_tp.rds")
    
    seaObject_te <- NULL
    if (!is.null(te_val)) {
      seaObject_te <- createSeaObject(fracTable, parents, timepoints,
                                      timepointInterpolation = TRUE,
                                      therapyEffect = te_val)
      saveRDS(seaObject_te, "seaObject_te.rds")
    }
    
    seaObject_col <- createSeaObject(fracTable, parents, timepoints,
                                    timepointInterpolation = TRUE,
                                    col = colors_val)
    saveRDS(seaObject_col, "seaObject_col.rds")
    
    # -----------------------------------------------------------------------------
    # 4. Generate Shark Plots
    # -----------------------------------------------------------------------------
    save_pdf_plot("shark_plot_tp.pdf", 
                  sharkPlot(seaObject_tp, showLegend = TRUE, main = 'Example Shark plot'))
    
    save_pdf_plot("shark_plot_col.pdf", 
                  sharkPlot(seaObject_col, showLegend = TRUE, main = 'Example Shark plot'))
    
    # Extended Shark Plot (Interactive Widget)
    esp_widget <- extSharkPlot(seaObject_tp, timepoints = timepoints, showLegend = TRUE, 
                               main = 'Example Extended Shark plot')
    save_widget_plot("extended_shark_plot.html", esp_widget)
    
    # Extended Shark Plot (Static PDF)
    save_pdf_plot("extended_shark_plot_static.pdf", 
                  extSharkPlot(seaObject_tp, timepoints = timepoints, showLegend = TRUE, 
                               main = 'Example Extended Shark plot', interactivePlot = FALSE))
    
    # -----------------------------------------------------------------------------
    # 5. Generate Dolphin Plots
    # -----------------------------------------------------------------------------
    save_pdf_plot("dolphin_plot_tp_spline.pdf", 
                  dolphinPlot(seaObject_tp, showLegend = TRUE, 
                              vlines = timepoints(seaObject), 
                              vlab = timepoints(seaObject), vlabSize = 2, 
                              ylab = 'Cancer cell fractions (CCFs)',
                              markMeasuredTimepoints = timepoints))
    
    save_pdf_plot("dolphin_plot_tp_polygon.pdf", 
                  dolphinPlot(seaObject_tp, showLegend = TRUE, vlines = timepoints,
                              vlab = timepoints, vlabSize = 2, 
                              ylab = 'Cancer cell fractions (CCFs)', shape = 'polygon'))
    
    save_pdf_plot("dolphin_plot_tp_bottom.pdf", 
                  dolphinPlot(seaObject_tp, showLegend = FALSE,  vlines = timepoints,
                              vlab = timepoints, vlabSize = 2, 
                              ylab = 'Cancer cell fractions (CCFs)', 
                              separateIndependentClones = TRUE, pos = 'bottom'))
    
    save_pdf_plot("dolphin_plot_tp_annotated.pdf", 
                  dolphinPlot(seaObject_tp, showLegend = TRUE, main = 'Example Dolphin Plot', 
                              vlines = timepoints, vlab = timepoints, vlabSize = 2, 
                              ylab = 'Cancer cell fraction', annotations = annotsTable, 
                              pos = 'bottom', separateIndependentClones = TRUE))
    
    if (!is.null(seaObject_te)) {
      save_pdf_plot("dolphin_plot_te.pdf", 
                    dolphinPlot(seaObject_te, showLegend = TRUE, 
                                vlines = slot(seaObject,"timepoints"), 
                                vlab = slot(seaObject,"timepoints"), vlabSize = 2, 
                                ylab = 'Cancer cell fractions (CCFs)',
                                markMeasuredTimepoints = timepoints))
    }
    
    # -----------------------------------------------------------------------------
    # 6. Generate Combined Plots
    # -----------------------------------------------------------------------------
    # Save combined plot using the built-in downloadWidget parameter
    tryCatch({
      combinedPlot(seaObject_tp, showLegend = TRUE, vlines = timepoints,
                   vlab = timepoints, vlabSize = 2, ylab = 'Cancer cell fraction',
                   separateIndependentClones = TRUE, downloadWidget = "combined_plot.html")
      message("Successfully saved combined plot to combined_plot.html")
    }, error = function(e) {
      message("Failed to save combined plot: ", e\$message)
    })
    
    # -----------------------------------------------------------------------------
    # 7. Generate Plaice Plots
    # -----------------------------------------------------------------------------
    save_pdf_plot("plaice_plot_tp.pdf", 
                  plaicePlot(seaObject_tp, showLegend = TRUE,  vlines = timepoints,
                             vlab = timepoints, vlabSize = 4, ylab = TRUE, 
                             separateIndependentClones = TRUE))
    
    save_pdf_plot("plaice_plot_tp_biallelic.pdf", 
                  plaicePlot(seaObject_tp, showLegend = TRUE,  vlines = timepoints,
                             vlab = timepoints, vlabSize = 4, ylab = TRUE, 
                             separateIndependentClones = TRUE, clonesToFill = clonesToFill_val,
                             annotations = annotsTable))
    
    if (!is.null(seaObject_te)) {
      save_pdf_plot("plaice_plot_te.pdf", 
                    plaicePlot(seaObject_te, showLegend = TRUE,  vlines = timepoints,
                               vlab = timepoints, vlabSize = 4, ylab = TRUE, 
                               separateIndependentClones = TRUE))
    }
    
    # -----------------------------------------------------------------------------
    # 8. Explore Alternative Trees
    # -----------------------------------------------------------------------------
    tryCatch({
      trees <- exploreTrees(fracTable, timepoints)
      saveRDS(trees, "explored_trees.rds")
      message("Successfully explored alternative trees and saved to explored_trees.rds")
    }, error = function(e) {
      message("Failed to explore alternative trees: ", e\$message)
    })
    
    message("Pipeline execution completed successfully.")

    writeLines(c(
        '"BIOC_CLEVRVIS_STANDARD_CLONAL_VISUALIZATION":',
        paste0('    clevRvis: ', as.character(packageVersion('clevRvis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_clonal_visualization.csv versions.yml
    """
}

workflow BIOC_CLEVRVIS_STANDARD_CLONAL_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fracTable, parents, timepoints ] ]

    main:
    BIOC_CLEVRVIS_STANDARD_CLONAL_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_CLEVRVIS_STANDARD_CLONAL_VISUALIZATION.out.tables
    plots    = BIOC_CLEVRVIS_STANDARD_CLONAL_VISUALIZATION.out.plots
    objects  = BIOC_CLEVRVIS_STANDARD_CLONAL_VISUALIZATION.out.objects
    versions = BIOC_CLEVRVIS_STANDARD_CLONAL_VISUALIZATION.out.versions
}
