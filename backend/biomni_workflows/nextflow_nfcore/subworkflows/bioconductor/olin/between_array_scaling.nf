#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OLIN — between_array_scaling
// Scale the log ratios (M) across multiple normalized microarray slides in a batch to achieve a similar overall distribution.
// Input: normalized_microarray_data.RData
// Container: quay.io/biocontainers/bioconductor-olin:1.88.0--r45hdfd78af_0
// R packages: OLIN, marray
// Bioconductor: 3.20 | R: 4.4
// Requires: OLIN, marray
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load normalized microarray data
//  * 2. [Visualization & Output] Plot density distributions of log ratios for all arrays before scaling
//  * 3. [Core Analysis] Perform between-array scaling using variance, MAD, or quantile methods
//  * 4. [Visualization & Output] Plot density distributions after scaling to confirm alignment

nextflow.enable.dsl = 2

process BIOC_OLIN_BETWEEN_ARRAY_SCALING {
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
    .bm_deps <- c("OLIN", "marray")
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
        library(OLIN)
        library(marray)
        
        # 1. Load normalized microarray data
        input_file <- "normalized_microarray_data.RData"
        if (!file.exists(input_file)) {
          stop(paste("Required input file missing:", input_file))
        }
        
        # Load the RData file into a temporary environment to avoid namespace pollution
        temp_env <- new.env()
        load(input_file, envir = temp_env)
        
        # Find the marrayNorm object
        marray_norm_name <- NULL
        for (name in ls(temp_env)) {
          if (inherits(get(name, envir = temp_env), "marrayNorm")) {
            marray_norm_name <- name
            break
          }
        }
        
        if (is.null(marray_norm_name)) {
          stop("No object of class 'marrayNorm' found in the loaded RData file.")
        }
        
        # Assign to the variable name used in the documented workflow
        sw.olin <- get(marray_norm_name, envir = temp_env)
        
        # Set up PDF output for the density plots
        pdf("between_array_scaling_plots.pdf", width = 12, height = 6)
        par(mfrow = c(1, 2))
        
        # 2. Plot density distributions of log ratios for all arrays before scaling
        M <- maM(sw.olin)
        num_arrays <- ncol(M)
        col <- rainbow(num_arrays)
        
        plot(density(M[, num_arrays], na.rm = TRUE), col=col[num_arrays], xlim=c(-2,2), main="Before Between-Array Scaling")
        if (num_arrays > 1) {
          for (i in 1:(num_arrays-1)){
            lines(density(M[, i], na.rm = TRUE), col=col[i])
          }
        }
        
        # 3. Perform between-array scaling using variance method
        sw.olin.s <- bas(sw.olin, mode="var")
        
        # 4. Plot density distributions after scaling to confirm alignment
        M <- maM(sw.olin.s)
        
        plot(density(M[, num_arrays], na.rm = TRUE), col=col[num_arrays], xlim=c(-2,2), main="After Between-Array Scaling")
        if (num_arrays > 1) {
          for (i in 1:(num_arrays-1)){
            lines(density(M[, i], na.rm = TRUE), col=col[i])
          }
        }
        
        dev.off()
        
        # Save the scaled marrayNorm object
        saveRDS(sw.olin.s, file = "scaled_microarray_data.rds")
        
        # Save the scaled log ratios (M) as a CSV table
        write.csv(M, file = "scaled_log_ratios.csv", row.names = TRUE)
        
        cat("Pipeline completed successfully.\n")
        cat("Outputs written:\n")
        cat("- between_array_scaling_plots.pdf (Density plots before and after scaling)\n")
        cat("- scaled_microarray_data.rds (Scaled marrayNorm object)\n")
        cat("- scaled_log_ratios.csv (CSV table of scaled log ratios)\n")

    writeLines(c(
        '"BIOC_OLIN_BETWEEN_ARRAY_SCALING":',
        paste0('    OLIN: ', as.character(packageVersion('OLIN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_between_array_scaling.csv versions.yml
    """
}

workflow BIOC_OLIN_BETWEEN_ARRAY_SCALING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ normalized_microarray_data.RData ] ]

    main:
    BIOC_OLIN_BETWEEN_ARRAY_SCALING(ch_input)

    emit:
    tables   = BIOC_OLIN_BETWEEN_ARRAY_SCALING.out.tables
    plots    = BIOC_OLIN_BETWEEN_ARRAY_SCALING.out.plots
    objects  = BIOC_OLIN_BETWEEN_ARRAY_SCALING.out.objects
    versions = BIOC_OLIN_BETWEEN_ARRAY_SCALING.out.versions
}
