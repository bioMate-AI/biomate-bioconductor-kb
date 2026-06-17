#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rnbeads — infinium_microarray_analysis
// Perform an automated end-to-end analysis of Infinium microarray data from raw IDAT files and sample annotations to generate comprehensive HTML reports.
// Input: idat, sample_annotation.csv
// Container: quay.io/biocontainers/bioconductor-rnbeads:2.28.0--r45hdfd78af_0
// R packages: ggplot2, RnBeads, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNBEADS_INFINIUM_MICROARRAY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rnbeads:2.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("ggplot2", "RnBeads", "rtracklayer")
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
    library(RnBeads)
    
    # Define input paths as specified by the user
    idat.dir <- "idat"
    sample.annotation <- "sample_annotation.csv"
    report.dir <- "rnbeads_reports"
    
    # Verify that the required user inputs exist
    if (!dir.exists(idat.dir)) {
      stop(paste("Error: IDAT directory '", idat.dir, "' not found in the working directory.", sep = ""))
    }
    
    if (!file.exists(sample.annotation)) {
      stop(paste("Error: Sample annotation file '", sample.annotation, "' not found in the working directory.", sep = ""))
    }
    
    # Pitfall prevention: The output report directory must not already exist prior to running the analysis.
    # If it exists, we remove it to prevent execution failure.
    if (dir.exists(report.dir)) {
      message("Removing existing report directory to prevent RnBeads execution failure...")
      unlink(report.dir, recursive = TRUE, force = TRUE)
    }
    
    # Write a preliminary summary of the sample annotation as a named output file
    message("Reading and summarizing sample annotation...")
    sa_data <- read.csv(sample.annotation, stringsAsFactors = FALSE)
    write.csv(sa_data, "input_sample_annotation_copy.csv", row.names = FALSE)
    
    # --- Set global analysis options (e.g., sex chromosome ---
    message("Setting RnBeads global options...")
    rnb.options(filtering.sex.chromosomes.removal=TRUE,
        identifiers.column="Sample_ID")
    
    # Save the configured options to a CSV file for traceability
    opts <- rnb.options()
    opts_df <- data.frame(
      Option = names(opts),
      Value = sapply(opts, function(x) paste(as.character(x), collapse = ", ")),
      stringsAsFactors = FALSE
    )
    write.csv(opts_df, "rnbeads_options_flat.csv", row.names = FALSE)
    
    # --- Run the complete analysis pipeline using the automated ---
    message("Starting RnBeads automated analysis pipeline...")
    pipeline_success <- tryCatch({
      rnb.run.analysis(dir.reports=report.dir, sample.sheet=sample.annotation,
          data.dir=idat.dir, data.type="infinium.idat.dir")
      TRUE
    }, error = function(e) {
      message("An error occurred during the RnBeads analysis pipeline:")
      message(e\$message)
      FALSE
    })
    
    # Write final pipeline status and output files
    if (pipeline_success && dir.exists(report.dir)) {
      message("RnBeads pipeline completed successfully. Reports generated in: ", report.dir)
      writeLines("SUCCESS", "pipeline_status.txt")
      
      # Attempt to locate and copy any generated RDS/RData objects from the report directory
      rnb_set_files <- list.files(path = report.dir, pattern = "\\\\.(RData|rds)\$", recursive = TRUE, full.names = TRUE)
      if (length(rnb_set_files) > 0) {
        for (i in seq_along(rnb_set_files)) {
          file.copy(rnb_set_files[i], paste0("extracted_analysis_object_", i, ".", tools::file_ext(rnb_set_files[i])))
        }
      }
    } else {
      message("RnBeads pipeline failed or did not produce the expected report directory.")
      writeLines("FAILED", "pipeline_status.txt")
    }

    writeLines(c(
        '"BIOC_RNBEADS_INFINIUM_MICROARRAY_ANALYSIS":',
        paste0('        rnbeads: ', as.character(packageVersion("rnbeads")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_infinium_microarray_analysis.csv versions.yml
    """
}

workflow BIOC_RNBEADS_INFINIUM_MICROARRAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ idat, sample_annotation.csv ] ]

    main:
    BIOC_RNBEADS_INFINIUM_MICROARRAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RNBEADS_INFINIUM_MICROARRAY_ANALYSIS.out.tables
    plots    = BIOC_RNBEADS_INFINIUM_MICROARRAY_ANALYSIS.out.plots
    objects  = BIOC_RNBEADS_INFINIUM_MICROARRAY_ANALYSIS.out.objects
    versions = BIOC_RNBEADS_INFINIUM_MICROARRAY_ANALYSIS.out.versions
}
