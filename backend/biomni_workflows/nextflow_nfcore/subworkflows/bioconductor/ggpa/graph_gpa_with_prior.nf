#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GGPA — graph_gpa_with_prior
// Fit a graph-GPA model incorporating an informative prior disease graph (e.g., downloaded from DDNet) to improve SNP prioritization and pleiotropic architecture 
// Input: pmat, pgraph
// Container: quay.io/biocontainers/bioconductor-ggpa:1.22.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GGPA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the graph-GPA model with the prior graph using GGPA
//  * 2. [Visualization & Output] Perform downstream association mapping and visualization using assoc, fdr, and plot

nextflow.enable.dsl = 2

process BIOC_GGPA_GRAPH_GPA_WITH_PRIOR {
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
    .bm_deps <- c("GGPA")
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
    library("GGPA")
    
    # Define input file paths (expected in the working directory)
    pmat_file <- "pmat.csv"
    pgraph_file <- "pgraph.csv"
    
    # Verify that the required input files exist
    if (!file.exists(pmat_file)) {
      stop(paste("Error: Required input file '", pmat_file, "' not found in the working directory.", sep=""))
    }
    if (!file.exists(pgraph_file)) {
      stop(paste("Error: Required input file '", pgraph_file, "' not found in the working directory.", sep=""))
    }
    
    # Read the input files
    # We assume standard CSV format with row names (e.g., SNP IDs) and column names (phenotypes)
    message("Reading p-value matrix...")
    pmat_df <- read.csv(pmat_file, header = TRUE, row.names = 1, check.names = FALSE)
    pmat <- as.matrix(pmat_df)
    
    message("Reading prior graph adjacency matrix...")
    pgraph_df <- read.csv(pgraph_file, header = TRUE, row.names = 1, check.names = FALSE)
    pgraph <- as.matrix(pgraph_df)
    
    # Validate inputs
    if (!all(colnames(pmat) == colnames(pgraph))) {
      stop("Error: Column names of 'pmat' and 'pgraph' must match exactly.")
    }
    if (nrow(pgraph) != ncol(pgraph)) {
      stop("Error: 'pgraph' must be a square adjacency matrix.")
    }
    
    # Set seed for reproducibility of MCMC
    set.seed(12345)
    
    # 1. Fit the graph-GPA model with the prior graph using GGPA
    message("Fitting graph-GPA model with prior graph...")
    fit <- GGPA( pmat, pgraph )
    
    # Display fit summary
    print(fit)
    
    # Save the fitted model object and estimates
    message("Saving model fit and parameter estimates...")
    saveRDS(fit, file = "ggpa_fit.rds")
    
    fit_estimates <- estimates(fit)
    saveRDS(fit_estimates, file = "ggpa_estimates.rds")
    
    # 2. Perform downstream association mapping and visualization
    message("Performing association mapping...")
    
    # Marginal association mapping
    assoc.marg <- assoc( fit, FDR=0.10, fdrControl="global" )
    write.csv(assoc.marg, file = "assoc_marginal.csv", row.names = TRUE)
    
    # Local FDR estimation
    fdr.marg <- fdr(fit)
    write.csv(fdr.marg, file = "fdr_marginal.csv", row.names = TRUE)
    
    # Joint association mapping for the first two phenotypes (i=1, j=2)
    # Ensuring we have at least 2 phenotypes to perform joint mapping
    if (ncol(pmat) >= 2) {
      message("Performing joint association mapping for phenotypes 1 and 2...")
      assoc.joint <- assoc( fit, FDR=0.10, fdrControl="global", i=1, j=2 )
      
      # Create a data frame to save joint association results alongside SNP IDs
      assoc_joint_df <- data.frame(
        SNP = rownames(pmat),
        Associated = assoc.joint,
        stringsAsFactors = FALSE
      )
      write.csv(assoc_joint_df, file = "assoc_joint_1_2.csv", row.names = FALSE)
    } else {
      message("Skipping joint association mapping: fewer than 2 phenotypes present.")
    }
    
    # Visualization of the estimated phenotype graph
    message("Generating phenotype graph plot...")
    pdf("estimated_phenotype_graph.pdf", width = 7, height = 7)
    tryCatch({
      plot(fit)
    }, error = function(e) {
      message("Warning: Plotting failed. Ensure appropriate graphical dependencies are installed.")
      message(e\$message)
    })
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_GGPA_GRAPH_GPA_WITH_PRIOR":',
        paste0('    GGPA: ', as.character(packageVersion('GGPA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_graph_gpa_with_prior.csv versions.yml
    """
}

workflow BIOC_GGPA_GRAPH_GPA_WITH_PRIOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pmat, pgraph ] ]

    main:
    BIOC_GGPA_GRAPH_GPA_WITH_PRIOR(ch_input)

    emit:
    tables   = BIOC_GGPA_GRAPH_GPA_WITH_PRIOR.out.tables
    plots    = BIOC_GGPA_GRAPH_GPA_WITH_PRIOR.out.plots
    objects  = BIOC_GGPA_GRAPH_GPA_WITH_PRIOR.out.objects
    versions = BIOC_GGPA_GRAPH_GPA_WITH_PRIOR.out.versions
}
