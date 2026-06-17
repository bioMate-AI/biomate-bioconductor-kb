#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Summix — local_ancestry_estimation
// Estimate local ancestry mixture proportions and optionally perform a selection scan along a chromosome.
// Input: ancestryData
// Container: quay.io/biocontainers/bioconductor-summix:2.16.0--r45hdfd78af_0
// R packages: Summix
// Bioconductor: 3.20 | R: 4.4
// Requires: Summix
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and data. 2. Run summix_local() to estimate local ancestry blocks and proportions

nextflow.enable.dsl = 2

process BIOC_SUMMIX_LOCAL_ANCESTRY_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    library(Summix)
    
    # Read user input file 'ancestryData' from the working directory
    # Supporting multiple common formats (CSV, TSV, TXT, RDS) for robustness
    if (file.exists("ancestryData.csv")) {
      ancestryData <- read.csv("ancestryData.csv", stringsAsFactors = FALSE)
    } else if (file.exists("ancestryData.tsv")) {
      ancestryData <- read.delim("ancestryData.tsv", stringsAsFactors = FALSE)
    } else if (file.exists("ancestryData.txt")) {
      ancestryData <- read.table("ancestryData.txt", header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("ancestryData.rds")) {
      ancestryData <- readRDS("ancestryData.rds")
    } else {
      stop("Error: Input file 'ancestryData' (CSV, TSV, TXT, or RDS) not found in the working directory.")
    }
    
    # Dynamically identify reference and observed columns
    all_cols <- colnames(ancestryData)
    meta_cols <- c("POS", "REF", "ALT", "CHROM", "ID", "SNP", "pos", "chr", "chrom")
    freq_cols <- setdiff(all_cols, meta_cols)
    
    # Robust identification of observed and reference columns
    observed_col <- grep("obs|gnomad", freq_cols, ignore.case = TRUE, value = TRUE)
    if (length(observed_col) != 1) {
      ref_candidates <- grep("ref", freq_cols, ignore.case = TRUE, value = TRUE)
      if (length(ref_candidates) > 0 && length(setdiff(freq_cols, ref_candidates)) == 1) {
        observed_col <- setdiff(freq_cols, ref_candidates)
      } else {
        observed_col <- tail(freq_cols, 1)
      }
    }
    reference_cols <- setdiff(freq_cols, observed_col)
    
    # Dynamically identify the position column
    pos_col_name <- intersect(c("POS", "pos", "position", "POSITION"), all_cols)[1]
    if (is.na(pos_col_name)) {
      pos_col_name <- "POS"
    }
    
    # Run local ancestry estimation using summix_local
    # NSimRef is removed as it is only required when selection_scan = TRUE
    results <- summix_local(data = ancestryData,
                            reference = reference_cols,
                            observed = observed_col,
                            goodness.of.fit = TRUE,
                            type = "variants",
                            algorithm = "fastcatch",
                            minVariants = 150,
                            maxVariants = 250,
                            maxStepSize = 1000,
                            diffThreshold = .02,
                            override_fit = FALSE,
                            override_removeSmallAnc = TRUE,
                            selection_scan = FALSE,
                            position_col = pos_col_name)
    
    # Print the results to standard output
    print(results\$results)
    
    # Write meaningful outputs to the working directory
    write.csv(results\$results, "local_ancestry_results.csv", row.names = FALSE)
    saveRDS(results, "local_ancestry_results.rds")

    writeLines(c(
        '"BIOC_SUMMIX_LOCAL_ANCESTRY_ESTIMATION":',
        paste0('    Summix: ', as.character(packageVersion('Summix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_local_ancestry_estimation.csv versions.yml
    """
}

workflow BIOC_SUMMIX_LOCAL_ANCESTRY_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ancestryData ] ]

    main:
    BIOC_SUMMIX_LOCAL_ANCESTRY_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_SUMMIX_LOCAL_ANCESTRY_ESTIMATION.out.tables
    plots    = BIOC_SUMMIX_LOCAL_ANCESTRY_ESTIMATION.out.plots
    objects  = BIOC_SUMMIX_LOCAL_ANCESTRY_ESTIMATION.out.objects
    versions = BIOC_SUMMIX_LOCAL_ANCESTRY_ESTIMATION.out.versions
}
