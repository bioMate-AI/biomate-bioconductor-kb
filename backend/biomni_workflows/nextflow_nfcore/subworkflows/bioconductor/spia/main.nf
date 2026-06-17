#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SPIA — standard_spia_analysis
// Perform Signaling Pathway Impact Analysis (SPIA) using pre-existing pathway data to identify significant pathways based on over-representation and topology pert
// Input: DE_Colorectal, ALL_Colorectal
// Container: quay.io/biocontainers/bioconductor-spia:2.62.0--r45hdfd78af_0
// R packages: graph, Rgraphviz, SPIA
// Bioconductor: 3.20 | R: 4.4
// Requires: SPIA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the SPIA analysis using the spia function
//  * 2. [Visualization & Output] Visualize the pathway significance using the plotP function
//  * 3. [Core Analysis] Recompute combined p-values using the combfunc function with the normal inversion method and adjust for multiple testing

nextflow.enable.dsl = 2

process BIOC_SPIA_STANDARD_SPIA_ANALYSIS {
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
    .bm_deps <- c("graph", "Rgraphviz", "SPIA")
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
    library(SPIA)
    
    # Helper function to robustly load DE_Colorectal
    load_de_colorectal <- function() {
      files_to_try <- c("DE_Colorectal", "DE_Colorectal.rds", "DE_Colorectal.csv", "DE_Colorectal.txt")
      for (f in files_to_try) {
        if (file.exists(f)) {
          # Try reading as RDS
          res <- tryCatch(readRDS(f), error = function(e) NULL)
          if (!is.null(res) && is.numeric(res) && !is.null(names(res))) {
            return(res)
          }
          
          # Try reading as CSV/TSV
          res <- tryCatch({
            df <- read.csv(f, header = TRUE, stringsAsFactors = FALSE, row.names = 1)
            vec <- as.numeric(df[[1]])
            names(vec) <- rownames(df)
            vec
          }, error = function(e) NULL)
          if (!is.null(res) && is.numeric(res)) return(res)
          
          res <- tryCatch({
            df <- read.table(f, header = FALSE, stringsAsFactors = FALSE)
            vec <- as.numeric(df[, 2])
            names(vec) <- as.character(df[, 1])
            vec
          }, error = function(e) NULL)
          if (!is.null(res) && is.numeric(res)) return(res)
        }
      }
      stop("Error: Could not find or read 'DE_Colorectal' in the working directory.")
    }
    
    # Helper function to robustly load ALL_Colorectal
    load_all_colorectal <- function() {
      files_to_try <- c("ALL_Colorectal", "ALL_Colorectal.rds", "ALL_Colorectal.csv", "ALL_Colorectal.txt")
      for (f in files_to_try) {
        if (file.exists(f)) {
          # Try reading as RDS
          res <- tryCatch(readRDS(f), error = function(e) NULL)
          if (!is.null(res) && (is.character(res) || is.numeric(res))) {
            return(as.character(res))
          }
          
          # Try reading as CSV/TSV/TXT
          res <- tryCatch({
            df <- read.csv(f, header = FALSE, stringsAsFactors = FALSE)
            as.character(df[[1]])
          }, error = function(e) NULL)
          if (!is.null(res)) return(res)
          
          res <- tryCatch({
            df <- read.table(f, header = FALSE, stringsAsFactors = FALSE)
            as.character(df[[1]])
          }, error = function(e) NULL)
          if (!is.null(res)) return(res)
        }
      }
      stop("Error: Could not find or read 'ALL_Colorectal' in the working directory.")
    }
    
    # 1. Read user input files
    DE_Colorectal <- load_de_colorectal()
    ALL_Colorectal <- load_all_colorectal()
    
    # 2. Run the SPIA analysis using the spia function (Fisher combination method)
    res <- spia(
      de = DE_Colorectal,
      all = ALL_Colorectal,
      organism = "hsa",
      nB = 2000,
      plots = FALSE,
      beta = NULL,
      combine = "fisher",
      verbose = FALSE
    )
    
    # 3. Visualize the pathway significance using the plotP function (Fisher method)
    pdf("spia_evidence_plot_fisher.pdf", width = 7, height = 7)
    plotP(res, threshold = 0.05)
    dev.off()
    
    # Save intermediate Fisher results
    write.csv(res, "spia_results_fisher.csv", row.names = FALSE)
    
    # 4. Recompute combined p-values using the combfunc function with the normal inversion method
    res\$pG <- combfunc(res\$pNDE, res\$pPERT, combine = "norminv")
    res\$pGFdr <- p.adjust(res\$pG, "fdr")
    res\$pGFWER <- p.adjust(res\$pG, "bonferroni")
    
    # 5. Visualize the pathway significance using the plotP function (Normal Inversion method)
    pdf("spia_evidence_plot_norminv.pdf", width = 7, height = 7)
    plotP(res, threshold = 0.05)
    dev.off()
    
    # 6. Write final outputs
    write.csv(res, "spia_results_norminv.csv", row.names = FALSE)
    saveRDS(res, "spia_results_final.rds")
    
    cat("SPIA pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_SPIA_STANDARD_SPIA_ANALYSIS":',
        paste0('    SPIA: ', as.character(packageVersion('SPIA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_spia_analysis.csv versions.yml
    """
}

workflow BIOC_SPIA_STANDARD_SPIA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ DE_Colorectal, ALL_Colorectal ] ]

    main:
    BIOC_SPIA_STANDARD_SPIA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SPIA_STANDARD_SPIA_ANALYSIS.out.tables
    plots    = BIOC_SPIA_STANDARD_SPIA_ANALYSIS.out.plots
    objects  = BIOC_SPIA_STANDARD_SPIA_ANALYSIS.out.objects
    versions = BIOC_SPIA_STANDARD_SPIA_ANALYSIS.out.versions
}
