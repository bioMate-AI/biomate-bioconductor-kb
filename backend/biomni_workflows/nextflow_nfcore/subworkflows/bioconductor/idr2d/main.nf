#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: idr2d — two_dimensional_idr
// Identify reproducible genomic interactions between two replicates of 2D genomic data (e.g., ChIA-PET, HiChIP, Hi-C).
// Input: rep1_df, rep2_df
// Container: quay.io/biocontainers/bioconductor-idr2d:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: idr2d
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load replicate data frames
//  * 2. [Core Analysis] Estimate 2D IDR using estimate_idr2d
//  * 3. [Visualization & Output] Summarize results using summary
//  * 4. [Visualization & Output] Visualize IDR distribution and dependencies using draw_idr_distribution_histogram, draw_rank_idr_scatterplot, and draw_value_idr_s

nextflow.enable.dsl = 2

process BIOC_IDR2D_TWO_DIMENSIONAL_IDR {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("idr2d")
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
    
    # 1. Load replicate data frames from the working directory
    if (file.exists("rep1_df.csv")) {
      rep1_df <- read.csv("rep1_df.csv", header = TRUE)
    } else if (file.exists("rep1_df.tsv")) {
      rep1_df <- read.delim("rep1_df.tsv", header = TRUE)
    } else if (file.exists("rep1_df.txt")) {
      rep1_df <- read.table("rep1_df.txt", header = TRUE)
    } else {
      stop("Could not find rep1_df input file (expected rep1_df.csv, rep1_df.tsv, or rep1_df.txt)")
    }
    
    if (file.exists("rep2_df.csv")) {
      rep2_df <- read.csv("rep2_df.csv", header = TRUE)
    } else if (file.exists("rep2_df.tsv")) {
      rep2_df <- read.delim("rep2_df.tsv", header = TRUE)
    } else if (file.exists("rep2_df.txt")) {
      rep2_df <- read.table("rep2_df.txt", header = TRUE)
    } else {
      stop("Could not find rep2_df input file (expected rep2_df.csv, rep2_df.tsv, or rep2_df.txt)")
    }
    
    # Load the package
    library(idr2d)
    
    # 2. Estimate 2D IDR using estimate_idr2d
    idr_results <- estimate_idr2d(rep1_df, rep2_df,
                                  value_transformation = "log_additive_inverse")
    rep1_idr_df <- idr_results\$rep1_df
    
    # 3. Summarize results and save summary to a text file
    sink("idr_summary.txt")
    summary(idr_results)
    sink()
    
    # Print summary to console as well
    summary(idr_results)
    
    # 4. Visualize IDR distribution and dependencies, saving to a PDF file
    pdf("idr_plots.pdf", width = 7, height = 7)
    print(draw_idr_distribution_histogram(rep1_idr_df))
    print(draw_rank_idr_scatterplot(rep1_idr_df))
    print(draw_value_idr_scatterplot(rep1_idr_df))
    dev.off()
    
    # Save meaningful results to files
    saveRDS(idr_results, "idr_results.rds")
    write.csv(rep1_idr_df, "rep1_idr_df.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_IDR2D_TWO_DIMENSIONAL_IDR":',
        paste0('    idr2d: ', as.character(packageVersion('idr2d')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_dimensional_idr.csv versions.yml
    """
}

workflow BIOC_IDR2D_TWO_DIMENSIONAL_IDR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rep1_df, rep2_df ] ]

    main:
    BIOC_IDR2D_TWO_DIMENSIONAL_IDR(ch_input)

    emit:
    tables   = BIOC_IDR2D_TWO_DIMENSIONAL_IDR.out.tables
    plots    = BIOC_IDR2D_TWO_DIMENSIONAL_IDR.out.plots
    objects  = BIOC_IDR2D_TWO_DIMENSIONAL_IDR.out.objects
    versions = BIOC_IDR2D_TWO_DIMENSIONAL_IDR.out.versions
}
