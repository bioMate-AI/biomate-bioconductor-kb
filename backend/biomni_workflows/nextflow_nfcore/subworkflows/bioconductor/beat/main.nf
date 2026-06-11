#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BEAT — single_cell_epimutation_analysis
// Quantify DNA methylation and call regional epimutations from single-cell bisulfite sequencing data compared to a reference sample.
// Input: reference.positions.csv, sample.positions.csv
// Container: quay.io/biocontainers/bioconductor-beat:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BEAT
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and define the local path and sample parameters using makeParams
//  * 2. [Core Analysis] Pool individual CpG counts into genomic regions using positions_to_regions
//  * 3. [Core Analysis] Model regional methylation rates and correct for experimental biases using generate_results
//  * 4. [Core Analysis] Call methylating and demethylating epimutations using epimutation_calls

nextflow.enable.dsl = 2

process BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS {
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
    .bm_deps <- c("BEAT")
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
    
    # Load the required BEAT library
    library(BEAT)
    
    # Define the local path as the current working directory where the user input files are located
    localpath <- getwd()
    
    # Verify that the required user input files exist in the working directory
    required_files <- c("reference.positions.csv", "sample.positions.csv")
    missing_files <- required_files[!file.exists(file.path(localpath, required_files))]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input file(s):", paste(missing_files, collapse = ", ")))
    }
    
    # Read and display the first few rows of the single-cell sample positions
    positions <- read.csv(file.path(localpath, "sample.positions.csv"))
    cat("--- First few rows of sample.positions.csv ---\n")
    print(head(positions))
    
    # Define sample names and reference status
    sampNames <- c('reference', 'sample')
    is.reference <- c(TRUE, FALSE)
    
    # Define conversion rates based on false positive rates (pplus)
    pplus <- c(0.2, 0.5)
    convrates <- 1 - pplus
    
    # Create the parameter object for the BEAT pipeline
    params <- makeParams(
      localpath = localpath,
      sampNames = sampNames,
      convrates = convrates,
      is.reference = is.reference,
      pminus = 0.2,
      regionSize = 10000,
      minCounts = 5
    )
    
    cat("\n--- Parameter Configuration ---\n")
    print(params)
    
    # Step 1: Pool individual CpG counts into genomic regions
    cat("\n--- Pooling CpG counts into regions ---\n")
    positions_to_regions(params)
    
    # Step 2: Model regional methylation rates and correct for experimental biases
    cat("\n--- Modeling regional methylation rates ---\n")
    generate_results(params)
    
    # Step 3: Call methylating and demethylating epimutations
    cat("\n--- Calling epimutations ---\n")
    epiCalls <- epimutation_calls(params)
    
    # Display the head of the epimutation calls if available
    cat("\n--- Methylating Epimutation Sites (First 3) ---\n")
    print(head(epiCalls\$methSites\$singlecell, 3))
    
    cat("\n--- Demethylating Epimutation Sites (First 3) ---\n")
    print(head(epiCalls\$demethSites\$singlecell, 3))
    
    # Save the final epimutation calls object to an RDS file for downstream analysis
    output_rds <- file.path(localpath, "epimutation_calls_results.rds")
    saveRDS(epiCalls, file = output_rds)
    cat(paste("\nPipeline completed successfully. Results saved to:", output_rds, "\n"))

    writeLines(c(
        '"BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS":',
        paste0('    BEAT: ', as.character(packageVersion('BEAT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_epimutation_analysis.csv versions.yml
    """
}

workflow BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reference.positions.csv, sample.positions.csv ] ]

    main:
    BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS.out.tables
    plots    = BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS.out.plots
    objects  = BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS.out.objects
    versions = BIOC_BEAT_SINGLE_CELL_EPIMUTATION_ANALYSIS.out.versions
}
