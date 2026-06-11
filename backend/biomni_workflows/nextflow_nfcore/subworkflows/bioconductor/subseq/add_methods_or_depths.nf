#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: subSeq — add_methods_or_depths
// Add a new analysis method or additional depths to a previous subsampling run using the same random seed to ensure comparability.
// Input: hammer.counts, subsamples, hammer.design$protocol
// Container: quay.io/biocontainers/bioconductor-subseq:1.40.0--r45hdfd78af_0
// R packages: subSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: subSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve the random seed from the original run using getSeed
//  * 2. [Core Analysis] Run subsample with the new method and the retrieved seed
//  * 3. [Core Analysis] Combine the original and new subsamples using combineSubsamples
//  * 4. [Visualization & Output] Summarize and plot the combined results

nextflow.enable.dsl = 2

process BIOC_SUBSEQ_ADD_METHODS_OR_DEPTHS {
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
    .bm_deps <- c("subSeq")
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
    
    # Load required libraries
    library(subSeq)
    
    # Helper functions to robustly load user input files from the working directory
    load_counts <- function() {
      if (file.exists("hammer.counts.rds")) {
        return(readRDS("hammer.counts.rds"))
      }
      if (file.exists("hammer.counts")) {
        obj <- tryCatch(readRDS("hammer.counts"), error = function(e) NULL)
        if (!is.null(obj)) return(obj)
        # Fallback to tab-separated/whitespace-separated table
        return(as.matrix(read.table("hammer.counts", header = TRUE, row.names = 1, check.names = FALSE)))
      }
      stop("Required input file 'hammer.counts' (or 'hammer.counts.rds') not found in the working directory.")
    }
    
    load_design <- function() {
      if (file.exists("hammer.design.rds")) {
        return(readRDS("hammer.design.rds"))
      }
      if (file.exists("hammer.design")) {
        obj <- tryCatch(readRDS("hammer.design"), error = function(e) NULL)
        if (!is.null(obj)) return(obj)
        # Fallback to table
        return(read.table("hammer.design", header = TRUE, row.names = 1, stringsAsFactors = FALSE))
      }
      stop("Required input file 'hammer.design' (or 'hammer.design.rds') not found in the working directory.")
    }
    
    load_subsamples <- function() {
      if (file.exists("subsamples.rds")) {
        return(readRDS("subsamples.rds"))
      }
      if (file.exists("subsamples")) {
        return(readRDS("subsamples"))
      }
      stop("Required input file 'subsamples' (or 'subsamples.rds') not found in the working directory.")
    }
    
    # Load inputs
    hammer.counts <- load_counts()
    subsamples <- load_subsamples()
    hammer.design <- load_design()
    
    # Ensure proportions are defined (extract from previous run to maintain consistency)
    if ("proportion" %in% colnames(subsamples)) {
      proportions <- unique(subsamples\$proportion)
    } else {
      proportions <- 10^seq(-2, 0, .5)
    }
    
    # --- BEGIN DOCUMENTED WORKFLOW ---
    
    seed = getSeed(subsamples)
    
    subsamples.more = subsample(hammer.counts, proportions, method=c("voomLimma"), treatment =hammer.design\$protocol, seed=seed)
    
    subsamples.combined = combineSubsamples(subsamples, subsamples.more)
    
    # Plotting and summarizing
    subsamples.summary <- summary(subsamples.combined)
    
    # --- END DOCUMENTED WORKFLOW ---
    
    # Write meaningful output files
    saveRDS(subsamples.combined, "subsamples.combined.rds")
    write.csv(as.data.frame(subsamples.summary), "subsamples.combined_summary.csv", row.names = FALSE)
    
    pdf("subsamples.combined_plot.pdf", width = 10, height = 8)
    plot(subsamples.summary)
    dev.off()

    writeLines(c(
        '"BIOC_SUBSEQ_ADD_METHODS_OR_DEPTHS":',
        paste0('    subSeq: ', as.character(packageVersion('subSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_add_methods_or_depths.csv versions.yml
    """
}

workflow BIOC_SUBSEQ_ADD_METHODS_OR_DEPTHS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hammer.counts, subsamples, hammer.design$protocol ] ]

    main:
    BIOC_SUBSEQ_ADD_METHODS_OR_DEPTHS(ch_input)

    emit:
    tables   = BIOC_SUBSEQ_ADD_METHODS_OR_DEPTHS.out.tables
    plots    = BIOC_SUBSEQ_ADD_METHODS_OR_DEPTHS.out.plots
    objects  = BIOC_SUBSEQ_ADD_METHODS_OR_DEPTHS.out.objects
    versions = BIOC_SUBSEQ_ADD_METHODS_OR_DEPTHS.out.versions
}
