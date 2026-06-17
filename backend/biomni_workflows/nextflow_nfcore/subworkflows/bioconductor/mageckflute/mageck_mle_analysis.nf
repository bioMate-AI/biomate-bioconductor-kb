#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MAGeCKFlute — mageck_mle_analysis
// Perform downstream quality control, visualization, and functional enrichment analysis on CRISPR screen results processed via the MAGeCK MLE (Maximum Likelihood 
// Input: gene_summary.txt
// Container: quay.io/biocontainers/bioconductor-mageckflute:2.9.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MAGeCKFlute
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the MLE gene summary file containing beta scores
//  * 2. [Core Analysis] Run the FluteMLE pipeline to identify essential genes across conditions and perform pathway enrichment analysis

nextflow.enable.dsl = 2

process BIOC_MAGECKFLUTE_MAGECK_MLE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("MAGeCKFlute")
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
    library(MAGeCKFlute)
    
    # Define input file
    input_file <- "gene_summary.txt"
    
    # Verify input file existence
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file '", input_file, "' not found in the working directory.", sep = ""))
    }
    
    # 1. Read the MLE gene summary file containing beta scores
    message("Reading MAGeCK MLE gene summary data...")
    mle_data <- read.delim(input_file, check.names = FALSE)
    
    # Save a copy of the input data as an RDS object for reproducibility/traceability
    saveRDS(mle_data, file = "mle_data_input.rds")
    
    # Extract condition names from the columns (e.g., 'Condition|beta')
    beta_cols <- grep("\\\\|beta\$", colnames(mle_data), value = TRUE)
    conditions <- gsub("\\\\|beta\$", "", beta_cols)
    
    # 2. Run the FluteMLE pipeline to identify essential genes across conditions and perform pathway enrichment analysis
    message("Running FluteMLE pipeline...")
    # Using the exact documented function call and arguments
    if (length(conditions) >= 2) {
      FluteMLE(
        mle_data, 
        treatname = conditions[2], 
        ctrlname = conditions[1], 
        proj = "MLE_Project", 
        organism = "hsa", 
        outdir = "./"
      )
    } else if (length(conditions) == 1) {
      FluteMLE(
        mle_data, 
        treatname = conditions[1], 
        proj = "MLE_Project", 
        organism = "hsa", 
        outdir = "./"
      )
    } else {
      FluteMLE(
        mle_data, 
        treatname = "Treatment", 
        ctrlname = "Control", 
        proj = "MLE_Project", 
        organism = "hsa", 
        outdir = "./"
      )
    }
    
    message("MAGeCKFlute MLE analysis completed successfully. Outputs are saved in the current directory with the prefix 'MLE_Project'.")

    writeLines(c(
        '"BIOC_MAGECKFLUTE_MAGECK_MLE_ANALYSIS":',
        paste0('    MAGeCKFlute: ', as.character(packageVersion('MAGeCKFlute')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mageck_mle_analysis.csv versions.yml
    """
}

workflow BIOC_MAGECKFLUTE_MAGECK_MLE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_summary.txt ] ]

    main:
    BIOC_MAGECKFLUTE_MAGECK_MLE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MAGECKFLUTE_MAGECK_MLE_ANALYSIS.out.tables
    plots    = BIOC_MAGECKFLUTE_MAGECK_MLE_ANALYSIS.out.plots
    objects  = BIOC_MAGECKFLUTE_MAGECK_MLE_ANALYSIS.out.objects
    versions = BIOC_MAGECKFLUTE_MAGECK_MLE_ANALYSIS.out.versions
}
