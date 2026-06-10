#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowClust — prior_based_clustering
// Perform robust clustering incorporating prior knowledge from an existing model fit.
// Input: rituximab2, res2
// Container: quay.io/biocontainers/bioconductor-flowclust:3.48.0--r45h01b2380_0
// R packages: flowClust, flowCore, flowStats
// Bioconductor: 3.20 | R: 4.4
// Requires: flowClust, flowCore, flowStats
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract prior parameters from an existing model using flowClust2Prior
//  * 2. [Core Analysis] Adjust prior parameters (means, variances)
//  * 3. [Core Analysis] Run flowClust with the prior and usePrior="yes"
//  * 4. [Visualization & Output] Plot and compare results

nextflow.enable.dsl = 2

process BIOC_FLOWCLUST_PRIOR_BASED_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("flowClust", "flowCore", "flowStats")
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
    library(flowClust)
    library(flowCore)
    library(flowStats)
    
    # Helper function to read inputs robustly
    read_input <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else {
        stop(paste("Input file not found:", filename))
      }
    }
    
    # Read user inputs
    rituximab2 <- read_input("rituximab2")
    res2 <- read_input("res2")
    
    # Set seed for reproducibility
    set.seed(100)
    
    # Stage 1: Extract prior parameters from an existing model using flowClust2Prior
    prior <- flowClust2Prior(res2[[2]], kappa = 1, Nt = 5000)
    
    # Stage 2: Adjust prior parameters (means, variances)
    prior2 <- prior
    prior2\$Mu0[1, ] <- rep(box(200, prior2\$lambda), 2)
    prior2\$Lambda0 <- prior2\$Lambda0 / 2
    
    # Stage 3: Run flowClust with the prior and usePrior="yes"
    pfit2 <-
    	flowClust(
    		rituximab2,
    		varNames = c("FL1.H", "FL3.H"),
    		K = 2,
    		prior = prior2,
    		usePrior = "yes"
    	)
    
    # Save the fitted model object
    saveRDS(pfit2, "pfit2.rds")
    
    # Save summary statistics
    summary_df <- data.frame(
      Cluster = seq_len(pfit2@K),
      Proportion = pfit2@w
    )
    write.csv(summary_df, "pfit2_summary.csv", row.names = FALSE)
    
    # Stage 4: Plot and compare results
    pdf("prior_clustering_comparison.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    plot(res2[[2]], data = rituximab2)
    plot(pfit2, data = rituximab2)
    dev.off()

    writeLines(c(
        '"BIOC_FLOWCLUST_PRIOR_BASED_CLUSTERING":',
        paste0('    flowClust: ', as.character(packageVersion('flowClust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prior_based_clustering.csv versions.yml
    """
}

workflow BIOC_FLOWCLUST_PRIOR_BASED_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rituximab2, res2 ] ]

    main:
    BIOC_FLOWCLUST_PRIOR_BASED_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_FLOWCLUST_PRIOR_BASED_CLUSTERING.out.tables
    plots    = BIOC_FLOWCLUST_PRIOR_BASED_CLUSTERING.out.plots
    objects  = BIOC_FLOWCLUST_PRIOR_BASED_CLUSTERING.out.objects
    versions = BIOC_FLOWCLUST_PRIOR_BASED_CLUSTERING.out.versions
}
