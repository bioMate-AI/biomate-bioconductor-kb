#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mitch — standard_multi_contrast_enrichment
// Perform multi-contrast pathway enrichment analysis on differential expression data (e.g., RNA-seq) using gene sets from a GMT file.
// Input: ReactomePathways.gmt, rna, k9a
// Container: quay.io/biocontainers/bioconductor-mitch:1.22.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mitch
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Import gene sets from a GMT file using gmt_import
//  * 2. [Visualization & Output] Import and merge multi-contrast profiling data using
//  * 3. [Visualization & Output] Calculate multivariate enrichment using mitch_calc
//  * 4. [Visualization & Output] Generate an interactive HTML report using mitch_report
//  * 5. [Visualization & Output] Generate high-resolution PDF plots using mitch_plots
//  * 6. [Visualization & Output] Visualize gene set similarity and driver genes using

nextflow.enable.dsl = 2

process BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("mitch")
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
    
    # Load required library
    library("mitch")
    
    # --- Import gene sets from a GMT file using gmt_import ---
    if (!file.exists("ReactomePathways.gmt")) {
      stop("Required input file 'ReactomePathways.gmt' is missing in the working directory.")
    }
    genesets <- gmt_import("ReactomePathways.gmt")
    
    # Helper function to read rna and k9a data frames robustly from the working directory
    read_input_df <- function(filepath) {
      if (!file.exists(filepath)) {
        stop(paste("Required input file missing:", filepath))
      }
      # Try reading as RDS first, then TSV, then CSV
      df <- tryCatch({
        readRDS(filepath)
      }, error = function(e) {
        tryCatch({
          read.table(filepath, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
        }, error = function(e2) {
          read.csv(filepath, header = TRUE, row.names = 1, check.names = FALSE)
        })
      })
      return(df)
    }
    
    # Read the user input files
    rna <- read_input_df("rna")
    k9a <- read_input_df("k9a")
    
    # --- Import and merge multi-contrast profiling data using ---
    x <- list("rna"=rna,"k9a"=k9a)
    y <- mitch_import(x,"edgeR")
    
    # --- Calculate multivariate enrichment using mitch_calc ---
    # We use the imported 'genesets' object instead of the forbidden 'genesetsExample'
    res <- mitch_calc(y,genesets,priority="effect",cores=2)
    
    # Save enrichment results table to CSV and RDS
    write.csv(res\$enrichment_result, "enrichment_results.csv", row.names = FALSE)
    saveRDS(res, "mitch_results.rds")
    
    # --- Generate an interactive HTML report using mitch_report ---
    mitch_report(res,"myreport.html",overwrite=TRUE)
    
    # --- Generate high-resolution PDF plots using mitch_plots ---
    mitch_plots(res,outfile="mycharts.pdf")
    
    # --- Visualize gene set similarity and driver genes using ---
    # Capture the network plot to a PDF file
    pdf("network_plots.pdf", width = 14, height = 6)
    tryCatch({
      networkplot(res,FDR=1,n_sets=10)
    }, error = function(e) {
      warning("networkplot failed: ", e\$message)
    })
    dev.off()
    
    # Retrieve and save the driver genes list
    ng <- tryCatch({
      network_genes(res,FDR=1,n_sets=10)
    }, error = function(e) {
      warning("network_genes failed: ", e\$message)
      NULL
    })
    
    if (!is.null(ng)) {
      saveRDS(ng, "network_genes.rds")
    }

    writeLines(c(
        '"BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT":',
        paste0('    mitch: ', as.character(packageVersion('mitch')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_multi_contrast_enrichment.csv versions.yml
    """
}

workflow BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ReactomePathways.gmt, rna, k9a ] ]

    main:
    BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT.out.tables
    plots    = BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT.out.plots
    objects  = BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT.out.objects
    versions = BIOC_MITCH_STANDARD_MULTI_CONTRAST_ENRICHMENT.out.versions
}
