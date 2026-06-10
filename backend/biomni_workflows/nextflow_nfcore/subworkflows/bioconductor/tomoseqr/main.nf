#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tomoseqr — reconstruct_and_visualize_3d_expression
// Reconstruct 3D gene expression patterns from 3-axis Tomo-seq data and a spatial mask, then visualize the results.
// Input: testx, testy, testz, mask
// Container: quay.io/biocontainers/bioconductor-tomoseqr:1.14.0--r45hdfd78af_0
// R packages: tomoseqr
// Bioconductor: 3.20 | R: 4.4
// Requires: tomoseqr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and input data
//  * 2. [Core Analysis] Reconstruct 3D expression patterns for query genes using estimate3dExpressions
//  * 3. [Visualization & Output] Visualize the reconstructed 3D expression using the interactive imageViewer Shiny app

nextflow.enable.dsl = 2

process BIOC_TOMOSEQR_RECONSTRUCT_AND_VISUALIZE_3D_EXPRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("tomoseqr")
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
        
    # 1. Load the package and input data
    library(tomoseqr)
    
    # Helper function to read expression data frames from various formats
    read_expression_data <- function(base_name) {
      rds_path <- paste0(base_name, ".rds")
      csv_path <- paste0(base_name, ".csv")
      tsv_path <- paste0(base_name, ".tsv")
      
      if (file.exists(rds_path)) {
        return(readRDS(rds_path))
      } else if (file.exists(csv_path)) {
        return(read.csv(csv_path, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE))
      } else if (file.exists(tsv_path)) {
        return(read.delim(tsv_path, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE))
      } else {
        stop(sprintf("Required input file for '%s' not found (expected .rds, .csv, or .tsv)", base_name))
      }
    }
    
    # Read Tomo-seq expression data frames from the working directory
    testx <- read_expression_data("testx")
    testy <- read_expression_data("testy")
    testz <- read_expression_data("testz")
    
    # Read the 3D binary mask matrix from the working directory
    if (file.exists("mask.rds")) {
      mask <- readRDS("mask.rds")
    } else {
      stop("Required 3D mask file 'mask.rds' not found in the working directory.")
    }
    
    # 2. Reconstruct 3D expression patterns for query genes using estimate3dExpressions
    # Dynamically select the first few genes from the input data to avoid hardcoding
    query_genes <- head(testx[[1]], 3)
    
    tomoObj <- estimate3dExpressions(
        testx,
        testy,
        testz,
        mask = mask,
        query = query_genes
    )
    
    # Save the reconstructed 3D expression object to disk
    saveRDS(tomoObj, file = "tomoObj.rds")
    
    # 3. Visualize the reconstructed 3D expression using the interactive imageViewer Shiny app
    # Wrapped in a tryCatch block to prevent blocking/failure in non-interactive or headless environments
    tryCatch({
        imageViewer(tomoObj)
    }, error = function(e) {
        message("Note: Interactive imageViewer Shiny app could not be launched (expected in non-interactive sessions): ", e\$message)
    })

    writeLines(c(
        '"BIOC_TOMOSEQR_RECONSTRUCT_AND_VISUALIZE_3D_EXPRESSION":',
        paste0('    tomoseqr: ', as.character(packageVersion('tomoseqr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reconstruct_and_visualize_3d_expression.csv versions.yml
    """
}

workflow BIOC_TOMOSEQR_RECONSTRUCT_AND_VISUALIZE_3D_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ testx, testy, testz, mask ] ]

    main:
    BIOC_TOMOSEQR_RECONSTRUCT_AND_VISUALIZE_3D_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_TOMOSEQR_RECONSTRUCT_AND_VISUALIZE_3D_EXPRESSION.out.tables
    plots    = BIOC_TOMOSEQR_RECONSTRUCT_AND_VISUALIZE_3D_EXPRESSION.out.plots
    objects  = BIOC_TOMOSEQR_RECONSTRUCT_AND_VISUALIZE_3D_EXPRESSION.out.objects
    versions = BIOC_TOMOSEQR_RECONSTRUCT_AND_VISUALIZE_3D_EXPRESSION.out.versions
}
