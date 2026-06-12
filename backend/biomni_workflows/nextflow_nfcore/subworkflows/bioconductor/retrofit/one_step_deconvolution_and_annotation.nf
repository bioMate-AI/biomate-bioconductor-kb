#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: retrofit — one_step_deconvolution_and_annotation
// Deconvolve spatial transcriptomics data and annotate cell-type proportions simultaneously in a single step using a single-cell reference.
// Input: x, sc_ref_w
// Container: quay.io/biocontainers/bioconductor-retrofit:1.10.0--r45ha27e39d_0
// R packages: retrofit
// Bioconductor: 3.20 | R: 4.4
// Requires: retrofit
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Initialize Parameters and Run Joint Deconvolution &
//  * 3. [Core Analysis] Save Outputs

nextflow.enable.dsl = 2

process BIOC_RETROFIT_ONE_STEP_DECONVOLUTION_AND_ANNOTATION {
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
    .bm_deps <- c("retrofit")
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
        library(retrofit)
        
        # -----------------------------------------------------------------------------
        # --- Read User Input Files ---
        # -----------------------------------------------------------------------------
        # The pipeline expects 'x' (Spatial transcriptomics gene expression matrix, G x S)
        # and 'sc_ref_w' (Single-cell reference matrix, G x K) in the working directory.
        # Supported formats: RDS (.rds) or CSV (.csv).
        
        x_path_rds <- "x.rds"
        x_path_csv <- "x.csv"
        sc_ref_w_path_rds <- "sc_ref_w.rds"
        sc_ref_w_path_csv <- "sc_ref_w.csv"
        
        # Load Spatial Transcriptomics Matrix (x)
        if (file.exists(x_path_rds)) {
          x <- readRDS(x_path_rds)
        } else if (file.exists(x_path_csv)) {
          x <- as.matrix(read.csv(x_path_csv, row.names = 1, check.names = FALSE))
        } else {
          stop("Error: Spatial transcriptomics matrix file ('x.rds' or 'x.csv') not found in the working directory.")
        }
        
        # Load Single-Cell Reference Matrix (sc_ref_w)
        if (file.exists(sc_ref_w_path_rds)) {
          sc_ref_w <- readRDS(sc_ref_w_path_rds)
        } else if (file.exists(sc_ref_w_path_csv)) {
          sc_ref_w <- as.matrix(read.csv(sc_ref_w_path_csv, row.names = 1, check.names = FALSE))
        } else {
          stop("Error: Single-cell reference matrix file ('sc_ref_w.rds' or 'sc_ref_w.csv') not found in the working directory.")
        }
        
        # -----------------------------------------------------------------------------
        # --- Initialize Parameters and Run Joint Deconvolution & ---
        # -----------------------------------------------------------------------------
        iterations = 4000
        L = 20
        K = ncol(sc_ref_w) 
        
        result = retrofit::retrofit(x, 
                                     sc_ref=sc_ref_w,
                                     iterations=iterations, 
                                     L=L, 
                                     K=K)
        
        # -----------------------------------------------------------------------------
        # --- Save Outputs ---
        # -----------------------------------------------------------------------------
        # Save the complete result object as an RDS file
        saveRDS(result, "retrofit_result.rds")
        
        # Export individual components (e.g., estimated proportions, profiles) to CSV
        if (is.list(result)) {
          for (name in names(result)) {
            val <- result[[name]]
            if (is.matrix(val) || is.data.frame(val)) {
              write.csv(val, paste0("retrofit_", name, ".csv"), row.names = TRUE)
            } else if (is.vector(val)) {
              write.csv(data.frame(Value = val), paste0("retrofit_", name, ".csv"), row.names = TRUE)
            }
          }
        }
        
        message("RETROFIT pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_RETROFIT_ONE_STEP_DECONVOLUTION_AND_ANNOTATION":',
        paste0('    retrofit: ', as.character(packageVersion('retrofit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_step_deconvolution_and_annotation.csv versions.yml
    """
}

workflow BIOC_RETROFIT_ONE_STEP_DECONVOLUTION_AND_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ x, sc_ref_w ] ]

    main:
    BIOC_RETROFIT_ONE_STEP_DECONVOLUTION_AND_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_RETROFIT_ONE_STEP_DECONVOLUTION_AND_ANNOTATION.out.tables
    plots    = BIOC_RETROFIT_ONE_STEP_DECONVOLUTION_AND_ANNOTATION.out.plots
    objects  = BIOC_RETROFIT_ONE_STEP_DECONVOLUTION_AND_ANNOTATION.out.objects
    versions = BIOC_RETROFIT_ONE_STEP_DECONVOLUTION_AND_ANNOTATION.out.versions
}
