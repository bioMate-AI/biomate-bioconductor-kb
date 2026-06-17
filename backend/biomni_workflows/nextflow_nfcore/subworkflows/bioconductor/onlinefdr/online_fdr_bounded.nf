#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: onlineFDR — online_fdr_bounded
// Control the False Discovery Rate (FDR) when the user has an a priori expected bound on the total number of hypothesis tests.
// Input: sample.df
// Container: quay.io/biocontainers/bioconductor-onlinefdr:2.18.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: onlineFDR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the sequential dataset with p-values and dates. 2. Set a bound on the number of hypotheses using the `setBound` function. 3

nextflow.enable.dsl = 2

process BIOC_ONLINEFDR_ONLINE_FDR_BOUNDED {
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
    .bm_deps <- c("onlineFDR")
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
    library(onlineFDR)
    
    # Read user input file 'sample.df' from the working directory
    if (file.exists("sample.df")) {
      sample.df <- tryCatch({
        # Try reading as CSV
        df <- read.csv("sample.df", stringsAsFactors = FALSE)
        if (!all(c("id", "date", "pval") %in% colnames(df))) {
          stop("CSV does not contain required columns")
        }
        df
      }, error = function(e) {
        # Fallback to RDS if CSV reading fails or columns are missing
        readRDS("sample.df")
      })
    } else {
      stop("Required input file 'sample.df' not found in the working directory.")
    }
    
    # Ensure the date column is of Date class
    sample.df\$date <- as.Date(sample.df\$date)
    
    # Set a bound on the number of hypotheses (e.g., 20 hypotheses)
    bound <- setBound("LOND", alpha = 0.04, 20)
    
    # Run the LOND algorithm with the calculated bound
    set.seed(1)
    LOND_results <- LOND(sample.df, alpha = 0.04, betai = bound)
    
    # Write meaningful results to output files
    write.csv(LOND_results, "LOND_results.csv", row.names = FALSE)
    saveRDS(LOND_results, "LOND_results.rds")
    
    # Generate and save a plot of the adjusted significance thresholds
    pdf("LOND_thresholds.pdf")
    plot(
      seq_len(nrow(LOND_results)), 
      LOND_results\$alphai, 
      type = "b", 
      col = "blue", 
      pch = 19,
      xlab = "Hypothesis Index", 
      ylab = "Adjusted Alpha Threshold (alphai)", 
      main = "LOND Bounded Significance Thresholds"
    )
    grid()
    dev.off()

    writeLines(c(
        '"BIOC_ONLINEFDR_ONLINE_FDR_BOUNDED":',
        paste0('    onlineFDR: ', as.character(packageVersion('onlineFDR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_online_fdr_bounded.csv versions.yml
    """
}

workflow BIOC_ONLINEFDR_ONLINE_FDR_BOUNDED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.df ] ]

    main:
    BIOC_ONLINEFDR_ONLINE_FDR_BOUNDED(ch_input)

    emit:
    tables   = BIOC_ONLINEFDR_ONLINE_FDR_BOUNDED.out.tables
    plots    = BIOC_ONLINEFDR_ONLINE_FDR_BOUNDED.out.plots
    objects  = BIOC_ONLINEFDR_ONLINE_FDR_BOUNDED.out.objects
    versions = BIOC_ONLINEFDR_ONLINE_FDR_BOUNDED.out.versions
}
