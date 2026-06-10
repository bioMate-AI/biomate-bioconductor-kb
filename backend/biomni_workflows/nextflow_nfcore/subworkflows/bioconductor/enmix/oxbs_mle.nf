#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ENmix — oxbs_mle
// Estimate 5-methylcytosine (5mC) and 5-hydroxymethylcytosine (5hmC) levels from paired bisulfite (BS) and oxidative bisulfite (oxBS) data.
// Input: beta.BS, beta.oxBS, N.BS, N.oxBS
// Container: quay.io/biocontainers/bioconductor-enmix:1.46.1--r45hdfd78af_0
// Requires: ENmix
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load paired BS and oxBS data
//  * 2. [Core Analysis] Run Maximum Likelihood Estimation using oxBS.MLE

nextflow.enable.dsl = 2

process BIOC_ENMIX_OXBS_MLE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("ENmix")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(ENmix)
    
    # Helper function to robustly read user input files from the working directory
    read_input_file <- function(base_name) {
      possible_extensions <- c(".rds", ".csv", ".tsv", ".txt", "")
      
      for (ext in possible_extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          message(sprintf("Found file: %s. Loading...", file_path))
          
          # Read RDS files
          if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
            return(readRDS(file_path))
          }
          
          # Read delimited text files
          if (grepl("\\\\.(csv|tsv|txt)\$", file_path, ignore.case = TRUE) || ext == "") {
            sep <- if (grepl("\\\\.csv\$", file_path, ignore.case = TRUE)) "," else "\t"
            try_read <- tryCatch({
              df <- read.table(file_path, header = TRUE, sep = sep, row.names = 1, check.names = FALSE)
              as.matrix(df)
            }, error = function(e) {
              NULL
            })
            if (!is.null(try_read)) return(try_read)
          }
        }
      }
      stop(sprintf("Error: Required input file '%s' (with .rds, .csv, .tsv, or no extension) not found in the working directory.", base_name))
    }
    
    # Stage 1: Load paired BS and oxBS data from the working directory
    message("Loading user-provided paired BS and oxBS datasets...")
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    beta.BS   <- read_input_file("beta.BS")
    beta.oxBS <- read_input_file("beta.oxBS")
    N.BS      <- read_input_file("N.BS")
    N.oxBS    <- read_input_file("N.oxBS")
    
    # Validate that dimensions match across all inputs
    if (!all(dim(beta.BS) == dim(beta.oxBS)) || 
        !all(dim(beta.BS) == dim(N.BS)) || 
        !all(dim(beta.BS) == dim(N.oxBS))) {
      stop("Error: Dimensions of beta.BS, beta.oxBS, N.BS, and N.oxBS must be identical.")
    }
    
    # Stage 2: Run Maximum Likelihood Estimation using oxBS.MLE
    message("Running Maximum Likelihood Estimation (oxBS.MLE)...")
    resu <- oxBS.MLE(beta.BS, beta.oxBS, N.BS, N.oxBS)
    
    # Print dimensions of the results as documented
    message("Dimensions of estimated 5mC matrix:")
    print(dim(resu[["5mC"]]))
    
    message("Dimensions of estimated 5hmC matrix:")
    print(dim(resu[["5hmC"]]))
    
    # Stage 3: Write named output files for the results
    message("Saving results to output files...")
    
    # Save full results list as an RDS object
    saveRDS(resu, file = "oxBS_MLE_results.rds")
    
    # Save 5mC and 5hmC estimates as CSV tables
    write.csv(resu[["5mC"]], file = "estimated_5mC_levels.csv", row.names = TRUE)
    write.csv(resu[["5hmC"]], file = "estimated_5hmC_levels.csv", row.names = TRUE)
    
    # Generate and save distribution plots
    pdf("oxBS_MLE_distributions.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    tryCatch({
      # Use ENmix's fast frequency polygon plot if possible
      multifreqpoly(resu[["5mC"]], main = "Estimated 5mC Levels", xlab = "Beta Value")
      multifreqpoly(resu[["5hmC"]], main = "Estimated 5hmC Levels", xlab = "Beta Value")
    }, error = function(e) {
      # Fallback to standard density plots if multifreqpoly encounters issues
      plot(density(resu[["5mC"]], na.rm = TRUE), main = "Estimated 5mC Levels", xlab = "Beta Value", col = "blue")
      plot(density(resu[["5hmC"]], na.rm = TRUE), main = "Estimated 5hmC Levels", xlab = "Beta Value", col = "red")
    })
    dev.off()
    
    message("Pipeline completed successfully. Outputs written: 'oxBS_MLE_results.rds', 'estimated_5mC_levels.csv', 'estimated_5hmC_levels.csv', and 'oxBS_MLE_distributions.pdf'.")

    writeLines(c(
        '"BIOC_ENMIX_OXBS_MLE":',
        paste0('    ENmix: ', as.character(packageVersion('ENmix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_oxbs_mle.csv versions.yml
    """
}

workflow BIOC_ENMIX_OXBS_MLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ beta.BS, beta.oxBS, N.BS, N.oxBS ] ]

    main:
    BIOC_ENMIX_OXBS_MLE(ch_input)

    emit:
    tables   = BIOC_ENMIX_OXBS_MLE.out.tables
    plots    = BIOC_ENMIX_OXBS_MLE.out.plots
    objects  = BIOC_ENMIX_OXBS_MLE.out.objects
    versions = BIOC_ENMIX_OXBS_MLE.out.versions
}
