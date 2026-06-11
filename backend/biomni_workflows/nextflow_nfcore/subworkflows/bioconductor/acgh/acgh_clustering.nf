#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: aCGH — acgh_clustering
// Cluster samples based on copy number profiles of specific chromosomes and display with phenotype labels.
// Input: colorectal.na
// Container: quay.io/biocontainers/bioconductor-acgh:1.88.0--r45ha27e39d_0
// R packages: aCGH
// Bioconductor: 3.20 | R: 4.4
// Requires: aCGH
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Set up plotting layout
//  * 2. [Visualization & Output] Cluster samples and plot using clusterGenome

nextflow.enable.dsl = 2

process BIOC_ACGH_ACGH_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    .bm_deps <- c("aCGH")
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
        library(aCGH)
        
        # 1. Read the user input file
        # The pipeline expects 'colorectal.na' to be a serialized aCGH object (RDS format)
        if (!file.exists("colorectal.na")) {
          stop("Error: Required input file 'colorectal.na' not found in the working directory.")
        }
        
        colorectal.na <- readRDS("colorectal.na")
        
        # Extract phenotype variables needed for the clustering response
        sex <- phenotype(colorectal.na)\$sex
        sex.na <- !is.na(sex)
        
        # Subset the aCGH object to match the response vector
        colorectal.na <- colorectal.na[, sex.na, keep=TRUE]
        
        # 2. Set up plotting layout and run clustering
        # Output the plots to a PDF file
        pdf("acgh_clustering_plots.pdf", width = 10, height = 12)
        
        par(mfrow=c(2,1))
        
        # Cluster samples without separating by class
        clusterGenome(colorectal.na, response = sex[sex.na],
        		titles = c("Female", "Male"),
        		byclass = FALSE, showaber = TRUE, vecchrom = c(4,8,9),
        		dendPlot = FALSE, imp = FALSE)
        
        # Cluster samples by class (sex)
        clusterGenome(colorectal.na, response = sex[sex.na],
        		titles = c("Female", "Male"),
        		byclass = TRUE, showaber = TRUE, vecchrom = c(4,8,9),
        		dendPlot = FALSE, imp = FALSE)
        
        dev.off()
        
        # 3. Write a summary text file of the clustering run
        sink("clustering_summary.txt")
        cat("aCGH Clustering Workflow Summary\n")
        cat("================================\n\n")
        cat("Input Object: colorectal.na\n")
        cat("Number of Clones:", nrow(colorectal.na), "\n")
        cat("Number of Samples:", ncol(colorectal.na), "\n\n")
        cat("Response Variable (Sex) Distribution:\n")
        print(table(sex[sex.na], useNA = "ifany"))
        cat("\nClustering completed successfully. Plots saved to 'acgh_clustering_plots.pdf'.\n")
        sink()

    writeLines(c(
        '"BIOC_ACGH_ACGH_CLUSTERING":',
        paste0('    aCGH: ', as.character(packageVersion('aCGH')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_acgh_clustering.csv versions.yml
    """
}

workflow BIOC_ACGH_ACGH_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ colorectal.na ] ]

    main:
    BIOC_ACGH_ACGH_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_ACGH_ACGH_CLUSTERING.out.tables
    plots    = BIOC_ACGH_ACGH_CLUSTERING.out.plots
    objects  = BIOC_ACGH_ACGH_CLUSTERING.out.objects
    versions = BIOC_ACGH_ACGH_CLUSTERING.out.versions
}
