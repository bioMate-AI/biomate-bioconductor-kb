#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rbec — detect_contaminants
// Assess and predict contaminated samples based on the recruitment ratio of sequencing reads across samples.
// Input: log_path
// Container: quay.io/biocontainers/bioconductor-rbec:1.18.0--r45ha27e39d_0
// R packages: Rbec
// Bioconductor: 3.20 | R: 4.4
// Requires: Rbec
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] List all log files from the Rbec output
//  * 2. [Visualization & Output] Write the log file paths to a temporary text file
//  * 3. [Visualization & Output] Run Contam_detect to generate a contamination distribution plot and log file

nextflow.enable.dsl = 2

process BIOC_RBEC_DETECT_CONTAMINANTS {
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
    .bm_deps <- c("Rbec")
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
    
    # Load required library
    library(Rbec)
    
    # 1. List all log files from the Rbec output in the working directory
    # The user must provide the Rbec log files in the working directory or its subdirectories.
    log_path <- list.files(path = ".", pattern = "\\\\.log\$", recursive = TRUE, full.names = TRUE)
    
    if (length(log_path) == 0) {
      stop("Error: No Rbec log files (.log) found in the working directory. Please ensure the log files are present.")
    }
    
    # 2. Write the log file paths to a temporary text file
    log_file <- tempfile()
    writeLines(log_path, log_file)
    
    # Define a dedicated output directory for the contamination analysis results
    output_dir <- "contamination_analysis_outputs"
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE)
    }
    
    # 3. Run Contam_detect to generate a contamination distribution plot and log file
    Contam_detect(log_file, output_dir)
    
    # Print the location of the generated outputs
    cat("Contamination detection completed successfully.\n")
    cat("Outputs saved to directory:", output_dir, "\n")
    print(list.files(output_dir, full.names = TRUE))

    writeLines(c(
        '"BIOC_RBEC_DETECT_CONTAMINANTS":',
        paste0('    Rbec: ', as.character(packageVersion('Rbec')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detect_contaminants.csv versions.yml
    """
}

workflow BIOC_RBEC_DETECT_CONTAMINANTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ log_path ] ]

    main:
    BIOC_RBEC_DETECT_CONTAMINANTS(ch_input)

    emit:
    tables   = BIOC_RBEC_DETECT_CONTAMINANTS.out.tables
    plots    = BIOC_RBEC_DETECT_CONTAMINANTS.out.plots
    objects  = BIOC_RBEC_DETECT_CONTAMINANTS.out.objects
    versions = BIOC_RBEC_DETECT_CONTAMINANTS.out.versions
}
