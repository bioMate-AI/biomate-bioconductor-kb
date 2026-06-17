#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: microSTASIS — microbiota_stability_analysis
// Analyze and visualize the temporal stability of individual microbiotas using iterative clustering on paired samples.
// Input: paired_microbiome_data.rds
// Container: quay.io/biocontainers/bioconductor-microstasis:1.6.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, TreeSummarizedExperiment, ggplot2, microSTASIS
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Subset samples from paired time points
//  * 2. [Core Analysis] Run iterative clustering using the Hartigan-Wong k-means algorithm to stress-test paired samples
//  * 3. [Core Analysis] Validate the stability results
//  * 4. [Visualization & Output] Visualize the stability output

nextflow.enable.dsl = 2

process BIOC_MICROSTASIS_MICROBIOTA_STABILITY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("microSTASIS", "TreeSummarizedExperiment", "ggplot2", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
     library(SummarizedExperiment)
   library(microSTASIS)
    library(TreeSummarizedExperiment)
    library(ggplot2)
    
    # ----------------------------------------------------------------------
    # Step 0: Read User Input File
    # ----------------------------------------------------------------------
    input_file <- "paired_microbiome_data.rds"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    message("Reading paired microbiome data...")
    se <- readRDS(input_file)
    
    # Ensure the object is a SummarizedExperiment or TreeSummarizedExperiment
    if (!inherits(se, "SummarizedExperiment")) {
      stop("Error: Input object must be a SummarizedExperiment or TreeSummarizedExperiment.")
    }
    
    # Identify metadata columns dynamically
    coldata_cols <- colnames(colData(se))
    if (length(coldata_cols) < 2) {
      stop("Error: colData must contain at least two columns representing Subject ID and Time Point.")
    }
    
    # Heuristically identify the subject/individual column
    subject.col <- grep("subject|patient|individual|id|participant", coldata_cols, ignore.case = TRUE, value = TRUE)[1]
    if (is.na(subject.col)) {
      subject.col <- coldata_cols[1]
      message(paste("Warning: Could not automatically detect subject column. Defaulting to:", subject.col))
    } else {
      message(paste("Detected subject column:", subject.col))
    }
    
    # Heuristically identify the time/visit column
    time.col <- grep("time|visit|day|week|month|timepoint|stage", coldata_cols, ignore.case = TRUE, value = TRUE)[1]
    if (is.na(time.col)) {
      # Ensure we don't select the same column as subject
      remaining_cols <- setdiff(coldata_cols, subject.col)
      time.col <- remaining_cols[1]
      message(paste("Warning: Could not automatically detect time column. Defaulting to:", time.col))
    } else {
      message(paste("Detected time column:", time.col))
    }
    
    # Extract the first two unique time points for paired analysis
    time_vals_all <- unique(colData(se)[[time.col]])
    if (length(time_vals_all) < 2) {
      stop("Error: The time column must contain at least two distinct time points to perform paired analysis.")
    }
    time.vals <- time_vals_all[1:2]
    message(paste("Comparing time points:", paste(time.vals, collapse = " vs ")))
    
    # ----------------------------------------------------------------------
    # Step 1: Subset samples from paired time points
    # ----------------------------------------------------------------------
    message("Subsetting paired samples...")
    paired_se <- pairedSamples(
      x = se,
      subject.col = subject.col,
      time.col = time.col,
      time.vals = time.vals
    )
    
    # ----------------------------------------------------------------------
    # Step 2: Run iterative clustering (mStability)
    # ----------------------------------------------------------------------
    message("Running iterative clustering to assess microbiota stability...")
    
    # Determine a safe range of k (number of clusters) based on the number of subjects
    n_subjects <- length(unique(colData(paired_se)[[subject.col]]))
    max_k <- min(15, floor(n_subjects / 2))
    if (max_k < 2) {
      max_k <- 2
    }
    k.range <- 2:max_k
    message(paste("Using cluster range (k.range):", paste(k.range, collapse = " to ")))
    
    stability_res <- mStability(
      x = paired_se,
      subject.col = subject.col,
      time.col = time.col,
      k.range = k.range
    )
    
    # ----------------------------------------------------------------------
    # Step 3: Validate the stability results
    # ----------------------------------------------------------------------
    message("Validating stability results...")
    validation_res <- vStability(stability_res)
    
    # ----------------------------------------------------------------------
    # Step 4: Visualize the stability output
    # ----------------------------------------------------------------------
    message("Generating stability visualization...")
    p <- pStability(stability_res)
    
    # Save the plot
    plot_file <- "stability_plot.pdf"
    ggsave(plot_file, plot = p, width = 8, height = 6)
    message(paste("Saved stability plot to:", plot_file))
    
    # ----------------------------------------------------------------------
    # Step 5: Save Outputs
    # ----------------------------------------------------------------------
    message("Saving results to disk...")
    
    # Save RDS objects
    saveRDS(stability_res, "stability_results.rds")
    saveRDS(validation_res, "validation_results.rds")
    
    # Helper function to export data frames from results
    export_tables <- function(obj, prefix) {
      if (is.data.frame(obj)) {
        write.csv(obj, paste0(prefix, ".csv"), row.names = TRUE)
      } else if (is.list(obj)) {
        for (name in names(obj)) {
          sub_obj <- obj[[name]]
          if (is.data.frame(sub_obj)) {
            write.csv(sub_obj, paste0(prefix, "_", name, ".csv"), row.names = TRUE)
          } else if (is.matrix(sub_obj)) {
            write.csv(as.data.frame(sub_obj), paste0(prefix, "_", name, ".csv"), row.names = TRUE)
          }
        }
      }
    }
    
    export_tables(stability_res, "stability_results")
    export_tables(validation_res, "validation_results")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MICROSTASIS_MICROBIOTA_STABILITY_ANALYSIS":',
        paste0('    microSTASIS: ', as.character(packageVersion('microSTASIS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microbiota_stability_analysis.csv versions.yml
    """
}

workflow BIOC_MICROSTASIS_MICROBIOTA_STABILITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ paired_microbiome_data.rds ] ]

    main:
    BIOC_MICROSTASIS_MICROBIOTA_STABILITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MICROSTASIS_MICROBIOTA_STABILITY_ANALYSIS.out.tables
    plots    = BIOC_MICROSTASIS_MICROBIOTA_STABILITY_ANALYSIS.out.plots
    objects  = BIOC_MICROSTASIS_MICROBIOTA_STABILITY_ANALYSIS.out.objects
    versions = BIOC_MICROSTASIS_MICROBIOTA_STABILITY_ANALYSIS.out.versions
}
