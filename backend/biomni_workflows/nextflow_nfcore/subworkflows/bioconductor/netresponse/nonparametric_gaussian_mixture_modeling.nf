#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: netresponse — nonparametric_gaussian_mixture_modeling
// Fit an infinite Gaussian mixture model with a Variational Dirichlet Process approximation on multi-dimensional data.
// Input: D
// Container: quay.io/biocontainers/bioconductor-netresponse:1.70.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: netresponse
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit VDP mixture model using vdp.mixt
//  * 2. [Core Analysis] Extract estimated centroids
//  * 3. [Core Analysis] Retrieve hard mixture component assignments

nextflow.enable.dsl = 2

process BIOC_NETRESPONSE_NONPARAMETRIC_GAUSSIAN_MIXTURE_MODELING {
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
    .bm_deps <- c("netresponse")
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
    library(netresponse)
    
    # Read the user input file 'D' from the working directory
    # We support multiple common formats (CSV, TSV, RDS, or plain space-separated)
    if (file.exists("D")) {
      D <- as.matrix(read.table("D", header = TRUE, row.names = 1))
    } else if (file.exists("D.csv")) {
      D <- as.matrix(read.csv("D.csv", row.names = 1))
    } else if (file.exists("D.tsv")) {
      D <- as.matrix(read.delim("D.tsv", row.names = 1))
    } else if (file.exists("D.rds")) {
      D <- readRDS("D.rds")
    } else {
      stop("Error: Input file 'D' (matrix of multi-dimensional data) not found in the working directory.")
    }
    
    # Ensure D is a matrix
    D <- as.matrix(D)
    
    # To support the comparison calls from the documented code,
    # we attempt to load real/known cluster assignments and means if they are provided.
    # If not, we define sensible defaults so the code runs without error.
    if (file.exists("real.sample2comp.csv")) {
      real.sample2comp <- read.csv("real.sample2comp.csv")[, 1]
    } else if (file.exists("real_sample2comp.rds")) {
      real.sample2comp <- readRDS("real_sample2comp.rds")
    } else {
      # Default to a single dummy cluster if real assignments are unknown
      real.sample2comp <- rep(1, nrow(D))
    }
    
    if (file.exists("real.means.csv")) {
      real.means <- as.matrix(read.csv("real.means.csv", row.names = 1))
    } else if (file.exists("real_means.rds")) {
      real.means <- readRDS("real_means.rds")
    } else {
      # Default to the global column means of D
      real.means <- matrix(colMeans(D), nrow = 1)
    }
    
    # 1. Fit an infinite Gaussian mixture model with
    # Variational Dirichlet Process approximation
    mixt <- vdp.mixt( D )
    
    # 2. Centroids of the detected Gaussian components
    estimated.means <- mixt\$posterior\$centroids
    
    # 3. Hard mixture component assignment for each sample
    estimated.sample2comp <- apply(mixt\$posterior\$qOFz, 1, which.max)
    
    # Compare known and estimated mixture components
    # (note that cluster indices may have switched due to unidentifiability)
    # nearly all samples have one-to-one match between the real and estimated clusters
    comparison_table <- table(estimated.sample2comp, real.sample2comp)
    print(head(comparison_table))
    
    # Write meaningful output files
    write.csv(estimated.means, "estimated_means.csv", row.names = TRUE)
    write.csv(data.frame(Sample = rownames(D), Estimated_Cluster = estimated.sample2comp), 
              "estimated_assignments.csv", row.names = FALSE)
    write.csv(as.data.frame(comparison_table), "cluster_comparison_table.csv", row.names = TRUE)
    saveRDS(mixt, "vdp_mixture_model.rds")

    writeLines(c(
        '"BIOC_NETRESPONSE_NONPARAMETRIC_GAUSSIAN_MIXTURE_MODELING":',
        paste0('    netresponse: ', as.character(packageVersion('netresponse')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nonparametric_gaussian_mixture_modeling.csv versions.yml
    """
}

workflow BIOC_NETRESPONSE_NONPARAMETRIC_GAUSSIAN_MIXTURE_MODELING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ D ] ]

    main:
    BIOC_NETRESPONSE_NONPARAMETRIC_GAUSSIAN_MIXTURE_MODELING(ch_input)

    emit:
    tables   = BIOC_NETRESPONSE_NONPARAMETRIC_GAUSSIAN_MIXTURE_MODELING.out.tables
    plots    = BIOC_NETRESPONSE_NONPARAMETRIC_GAUSSIAN_MIXTURE_MODELING.out.plots
    objects  = BIOC_NETRESPONSE_NONPARAMETRIC_GAUSSIAN_MIXTURE_MODELING.out.objects
    versions = BIOC_NETRESPONSE_NONPARAMETRIC_GAUSSIAN_MIXTURE_MODELING.out.versions
}
