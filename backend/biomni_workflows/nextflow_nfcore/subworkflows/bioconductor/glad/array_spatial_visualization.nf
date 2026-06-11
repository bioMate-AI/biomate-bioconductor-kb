#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GLAD — array_spatial_visualization
// Visualize spatial layout and raw intensity values of CGH microarrays to detect experimental artifacts.
// Input: raw_array_data.txt
// Container: quay.io/biocontainers/bioconductor-glad:2.74.0--r45h1ca3914_0
// R packages: GLAD
// Bioconductor: 3.20 | R: 4.4
// Requires: GLAD
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create an arrayCGH object from a list containing arrayValues and arrayDesign
//  * 2. [Visualization & Output] Plot the spatial layout
//  * 3. [Visualization & Output] Plot the 3D perspective layout

nextflow.enable.dsl = 2

process BIOC_GLAD_ARRAY_SPATIAL_VISUALIZATION {
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
    .bm_deps <- c("GLAD")
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
    
    # Load required library
    library(GLAD)
    
    # 1. Read user input file
    input_file <- "raw_array_data.txt"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the table
    array2 <- read.table(input_file, header=TRUE, stringsAsFactors=FALSE)
    
    # Ensure Col and Row columns exist and are capitalized correctly
    colnames(array2)[tolower(colnames(array2)) == "col"] <- "Col"
    colnames(array2)[tolower(colnames(array2)) == "row"] <- "Row"
    
    if (!all(c("Col", "Row") %in% colnames(array2))) {
      stop("Error: Input file must contain 'Col' and 'Row' columns.")
    }
    
    # Ensure Log2Rat column exists
    if (!"Log2Rat" %in% colnames(array2)) {
      # Try to find a column representing log ratios
      log_cols <- grep("log", colnames(array2), ignore.case=TRUE, value=TRUE)
      if (length(log_cols) > 0) {
        colnames(array2)[colnames(array2) == log_cols[1]] <- "Log2Rat"
      } else {
        # Fallback: use the first column that is not Col or Row
        other_cols <- setdiff(colnames(array2), c("Col", "Row"))
        if (length(other_cols) > 0) {
          colnames(array2)[colnames(array2) == other_cols[1]] <- "Log2Rat"
        } else {
          stop("Error: Could not identify a log ratio column in the input file.")
        }
      }
    }
    
    # Ensure Col, Row, and Log2Rat are numeric
    array2\$Col <- as.numeric(array2\$Col)
    array2\$Row <- as.numeric(array2\$Row)
    array2\$Log2Rat <- as.numeric(array2\$Log2Rat)
    
    # Determine arrayDesign dynamically based on the input dimensions
    max_col <- max(array2\$Col, na.rm=TRUE)
    max_row <- max(array2\$Row, na.rm=TRUE)
    
    # Default design values (from vignette)
    arrayCol <- 4
    arrayRow <- 4
    SpotCol <- 21
    SpotRow <- 22
    
    # If dimensions differ from vignette, calculate a compatible design
    if (max_col != 88 || max_row != 84) {
      find_factors <- function(n) {
        which(n %% seq_len(n) == 0)
      }
      col_factors <- find_factors(max_col)
      row_factors <- find_factors(max_row)
      
      suitable_row_factors <- col_factors[col_factors >= 2 & col_factors <= 10]
      if (length(suitable_row_factors) > 0) {
        arrayRow <- suitable_row_factors[1]
        SpotRow <- max_col / arrayRow
      } else {
        arrayRow <- 1
        SpotRow <- max_col
      }
      
      suitable_col_factors <- row_factors[row_factors >= 2 & row_factors <= 10]
      if (length(suitable_col_factors) > 0) {
        arrayCol <- suitable_col_factors[1]
        SpotCol <- max_row / arrayCol
      } else {
        arrayCol <- 1
        SpotCol <- max_row
      }
    }
    
    arrayDesign <- c(arrayCol, arrayRow, SpotCol, SpotRow)
    
    # Create arrayCGH object
    array <- list(arrayValues=array2, arrayDesign=arrayDesign)
    class(array) <- "arrayCGH"
    
    # Save the constructed object
    saveRDS(array, file="array_cgh_object.rds")
    
    # 2. Plot the spatial layout
    pdf("spatial_array_plot.pdf", width=8, height=8)
    arrayPlot(array, "Log2Rat", bar="none")
    dev.off()
    
    # 3. Plot the 3D perspective layout
    pdf("spatial_array_persp.pdf", width=8, height=8)
    arrayPersp(array, "Log2Rat", box=FALSE, theta=110, phi=40, bar=FALSE)
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved: array_cgh_object.rds, spatial_array_plot.pdf, spatial_array_persp.pdf\n")

    writeLines(c(
        '"BIOC_GLAD_ARRAY_SPATIAL_VISUALIZATION":',
        paste0('    GLAD: ', as.character(packageVersion('GLAD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_array_spatial_visualization.csv versions.yml
    """
}

workflow BIOC_GLAD_ARRAY_SPATIAL_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_array_data.txt ] ]

    main:
    BIOC_GLAD_ARRAY_SPATIAL_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_GLAD_ARRAY_SPATIAL_VISUALIZATION.out.tables
    plots    = BIOC_GLAD_ARRAY_SPATIAL_VISUALIZATION.out.plots
    objects  = BIOC_GLAD_ARRAY_SPATIAL_VISUALIZATION.out.objects
    versions = BIOC_GLAD_ARRAY_SPATIAL_VISUALIZATION.out.versions
}
