#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ROTS — differential_expression_testing
// Perform differential expression testing on omics data using the Reproducibility-Optimized Test Statistic (ROTS) and visualize the results.
// Input: input, groups
// Container: quay.io/biocontainers/bioconductor-rots:2.2.0--r45ha27e39d_0
// R packages: ROTS
// Bioconductor: 3.20 | R: 4.4
// Requires: ROTS
// Visualizations: volcano plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and input data
//  * 2. [Input & Preparation] Define the experimental design groups
//  * 3. [Core Analysis] Run the ROTS optimization and differential testing
//  * 4. [Visualization & Output] Summarize the top-ranked features
//  * 5. [Visualization & Output] Visualize results with volcano and heatmap plots

nextflow.enable.dsl = 2

process BIOC_ROTS_DIFFERENTIAL_EXPRESSION_TESTING {
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
    .bm_deps <- c("ROTS")
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
            
    # 1. Load the package and input data
    library(ROTS)
    
    # Read input matrix
    if (file.exists("input.csv")) {
      input <- as.matrix(read.csv("input.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("input.tsv")) {
      input <- as.matrix(read.delim("input.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("input.txt")) {
      input <- as.matrix(read.table("input.txt", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Input matrix file ('input.csv', 'input.tsv', or 'input.txt') not found in the working directory.")
    }
    
    # 2. Define the experimental design groups
    if (file.exists("groups.txt")) {
      groups <- scan("groups.txt", what = character(), quiet = TRUE)
      if (!any(is.na(suppressWarnings(as.numeric(groups))))) {
        groups <- as.numeric(groups)
      } else {
        groups <- as.numeric(as.factor(groups))
      }
    } else if (file.exists("groups.csv")) {
      groups_df <- read.csv("groups.csv", header = FALSE, stringsAsFactors = FALSE)
      groups <- as.vector(t(groups_df))
      if (!any(is.na(suppressWarnings(as.numeric(groups))))) {
        groups <- as.numeric(groups)
      } else {
        groups <- as.numeric(as.factor(groups))
      }
    } else {
      stop("Error: Groups file ('groups.txt' or 'groups.csv') not found in the working directory.")
    }
    
    groups
    
    # 3. Run the ROTS optimization and differential testing
    results = ROTS(data = input, groups = groups , B = 100 , K = 500 , seed = 1234)
    names(results) 
    
    # 4. Summarize the top-ranked features
    summary(results, fdr = 0.05)
    
    # Save summary table to CSV
    sum_table <- summary(results, fdr = 0.05)
    if (!is.null(sum_table)) {
      write.csv(sum_table, file = "rots_summary.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(), file = "rots_summary.csv", row.names = FALSE)
    }
    
    # Save results object to RDS
    saveRDS(results, file = "rots_results.rds")
    
    # 5. Visualize results with volcano and heatmap plots
    pdf("rots_volcano_plot.pdf")
    plot(results, fdr = 0.05, type = "volcano")
    dev.off()
    
    pdf("rots_heatmap_plot.pdf")
    plot(results, fdr = 0.05, type = "heatmap")
    dev.off()

    writeLines(c(
        '"BIOC_ROTS_DIFFERENTIAL_EXPRESSION_TESTING":',
        paste0('    ROTS: ', as.character(packageVersion('ROTS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_expression_testing.csv versions.yml
    """
}

workflow BIOC_ROTS_DIFFERENTIAL_EXPRESSION_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input, groups ] ]

    main:
    BIOC_ROTS_DIFFERENTIAL_EXPRESSION_TESTING(ch_input)

    emit:
    tables   = BIOC_ROTS_DIFFERENTIAL_EXPRESSION_TESTING.out.tables
    plots    = BIOC_ROTS_DIFFERENTIAL_EXPRESSION_TESTING.out.plots
    objects  = BIOC_ROTS_DIFFERENTIAL_EXPRESSION_TESTING.out.objects
    versions = BIOC_ROTS_DIFFERENTIAL_EXPRESSION_TESTING.out.versions
}
