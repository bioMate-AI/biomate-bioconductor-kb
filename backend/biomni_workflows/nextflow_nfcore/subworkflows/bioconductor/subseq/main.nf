#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: subSeq — subsampling_depth_analysis
// Subsample a count matrix at multiple depths, run differential expression analyses, and evaluate the impact of depth on significance and effect size estimates.
// Input: hammer.counts, hammer.design$protocol
// Container: quay.io/biocontainers/bioconductor-subseq:1.40.0--r45hdfd78af_0
// R packages: ggplot2, subSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: subSeq
// Visualizations: plot (ggplot/base)
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out low-count genes
//  * 2. [Input & Preparation] Define logarithmic subsampling proportions
//  * 3. [Core Analysis] Perform subsampling and differential expression using subsample
//  * 4. [Visualization & Output] Summarize the subsamples using summary
//  * 5. [Visualization & Output] Plot the summary metrics using plot

nextflow.enable.dsl = 2

process BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS {
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
    .bm_deps <- c("ggplot2", "subSeq")
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
    
    # 1. Read the declared user input files from the working directory
    if (file.exists("hammer.counts")) {
      hammer.counts = tryCatch({
        readRDS("hammer.counts")
      }, error = function(e) {
        as.matrix(read.table("hammer.counts", header=TRUE, row.names=1, sep="", check.names=FALSE))
      })
    } else {
      stop("Error: 'hammer.counts' file not found in the working directory.")
    }
    
    if (file.exists("hammer.design\$protocol")) {
      protocol_vector = tryCatch({
        readRDS("hammer.design\$protocol")
      }, error = function(e) {
        readLines("hammer.design\$protocol")
      })
    } else {
      stop("Error: 'hammer.design\$protocol' file not found in the working directory.")
    }
    
    # Construct the hammer.design object to match the documented code's structure
    hammer.design = list(protocol = protocol_vector)
    
    # 2. Filter out low-count genes
    hammer.counts = hammer.counts[rowSums(hammer.counts) >= 5, ]
    
    # 3. Define logarithmic subsampling proportions
    proportions = 10^seq(-2, 0, .5)
    
    # 4. Perform subsampling and differential expression using subsample
    subsamples = subsample(hammer.counts, proportions, method=c("edgeR", "voomLimma"), treatment=hammer.design\$protocol)
    
    # 5. Summarize the subsamples using summary
    subsamples.summary = summary(subsamples)
    
    # 6. Plot the summary metrics using plot and save to PDF
    pdf("subsamples_summary_plots.pdf", width=10, height=8)
    plot(subsamples.summary)
    dev.off()
    
    # 7. Write additional meaningful outputs
    saveRDS(subsamples, "subsamples_results.rds")
    write.csv(as.data.frame(subsamples.summary), "subsamples_summary.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS":',
        paste0('    subSeq: ', as.character(packageVersion('subSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_subsampling_depth_analysis.csv versions.yml
    """
}

workflow BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hammer.counts, hammer.design$protocol ] ]

    main:
    BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS.out.tables
    plots    = BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS.out.plots
    objects  = BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS.out.objects
    versions = BIOC_SUBSEQ_SUBSAMPLING_DEPTH_ANALYSIS.out.versions
}
