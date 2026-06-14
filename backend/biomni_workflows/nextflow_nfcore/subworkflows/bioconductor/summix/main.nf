#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Summix — global_ancestry_estimation
// Estimate reference group proportions (global ancestry) in genetic summary allele frequency data.
// Input: ancestryData
// Container: quay.io/biocontainers/bioconductor-summix:2.16.0--r45hdfd78af_0
// R packages: Summix
// Bioconductor: 3.20 | R: 4.4
// Requires: Summix
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package
//  * 2. [Input & Preparation] Read the user input file 'ancestryData'
//  * 3. [Input & Preparation] Run summix to estimate reference ancestry proportions
//  * 4. [Input & Preparation] Write named output files

nextflow.enable.dsl = 2

process BIOC_SUMMIX_GLOBAL_ANCESTRY_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("Summix")
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
        
    # --- Load the package ---
    library(Summix)
    
    # --- Read the user input file 'ancestryData' ---
    # We check for common formats: CSV, TSV, or RDS
    if (file.exists("ancestryData.csv")) {
      ancestryData <- read.csv("ancestryData.csv", header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
    } else if (file.exists("ancestryData.tsv")) {
      ancestryData <- read.delim("ancestryData.tsv", header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
    } else if (file.exists("ancestryData.rds")) {
      ancestryData <- readRDS("ancestryData.rds")
    } else {
      stop("Required input file 'ancestryData' (CSV, TSV, or RDS) not found in the working directory.")
    }
    
    # Print head of the input data as documented
    print(head(ancestryData))
    
    # Dynamically identify reference and observed columns
    # Identify numeric columns to find allele frequencies
    is_num <- sapply(ancestryData, is.numeric)
    num_cols <- colnames(ancestryData)[is_num]
    
    # Exclude common numeric metadata columns
    meta_cols <- c("POS", "CHR", "CHROM", "BP", "position", "SNP", "ID")
    af_cols <- setdiff(num_cols, meta_cols)
    
    if (length(af_cols) < 2) {
      stop("Not enough numeric columns found for reference and observed data.")
    }
    
    # Assume the last allele frequency column is the observed group, and the rest are reference groups
    reference_cols <- af_cols[1:(length(af_cols) - 1)]
    observed_col <- af_cols[length(af_cols)]
    
    # --- Run summix to estimate reference ancestry proportions ---
    results <- summix(data = ancestryData,
        reference = reference_cols,
        observed = observed_col)
    
    # Print the results to console
    print(results)
    
    # --- Write named output files ---
    write.csv(results, "global_ancestry_proportions.csv", row.names = FALSE)
    saveRDS(results, "global_ancestry_proportions.rds")

    writeLines(c(
        '"BIOC_SUMMIX_GLOBAL_ANCESTRY_ESTIMATION":',
        paste0('    Summix: ', as.character(packageVersion('Summix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_global_ancestry_estimation.csv versions.yml
    """
}

workflow BIOC_SUMMIX_GLOBAL_ANCESTRY_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ancestryData ] ]

    main:
    BIOC_SUMMIX_GLOBAL_ANCESTRY_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_SUMMIX_GLOBAL_ANCESTRY_ESTIMATION.out.tables
    plots    = BIOC_SUMMIX_GLOBAL_ANCESTRY_ESTIMATION.out.plots
    objects  = BIOC_SUMMIX_GLOBAL_ANCESTRY_ESTIMATION.out.objects
    versions = BIOC_SUMMIX_GLOBAL_ANCESTRY_ESTIMATION.out.versions
}
