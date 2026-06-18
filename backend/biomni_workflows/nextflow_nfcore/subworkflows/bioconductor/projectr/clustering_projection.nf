#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: projectR — clustering_projection
// Define continuous weights for genes based on cluster membership and test for significant overlap between different clustering results.
// Input: target_expression.csv, cluster_assignments.csv
// Container: quay.io/biocontainers/bioconductor-projectr:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: gplots, projectR
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate continuous weights for genes based on their correlation to the mean of their assigned cluster using cluster2pattern
//  * 2. [Core Analysis] Test for statistically significant overlap between two sets of patterns or clusters using a hypergeometric test via intersectoR

nextflow.enable.dsl = 2

process BIOC_PROJECTR_CLUSTERING_PROJECTION {
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
    .bm_deps <- c("projectR")
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
    
    # Load required libraries
    library(projectR)
    
    # 1. Read User Inputs
    if (!file.exists("target_expression.csv")) {
      stop("Error: target_expression.csv not found in the working directory.")
    }
    if (!file.exists("cluster_assignments.csv")) {
      stop("Error: cluster_assignments.csv not found in the working directory.")
    }
    
    target_expression <- as.matrix(read.csv("target_expression.csv", row.names = 1, check.names = FALSE))
    cluster_assignments <- read.csv("cluster_assignments.csv", row.names = 1, check.names = FALSE)
    
    # 2. Prepare variables for documented workflow
    p.RNAseq6l3c3t <- target_expression
    
    # Determine number of clusters (nP) safely based on target expression dimensions
    nP <- min(5, ncol(p.RNAseq6l3c3t) - 1)
    if (nP < 2) {
      nP <- 2
    }
    
    # 3. Execute Documented Workflow Stage 1: cluster2pattern
    kClust<-kmeans(t(p.RNAseq6l3c3t),centers=nP)
    kpattern<-cluster2pattern(clusters = kClust, NP = nP, data = p.RNAseq6l3c3t)
    
    # 4. Prepare inputs for Documented Workflow Stage 2: intersectoR
    # Extract gene sets from kpattern (pSet1)
    kpattern_mat <- as.matrix(kpattern)
    pSet1 <- lapply(1:ncol(kpattern_mat), function(i) {
      rownames(kpattern_mat)[kpattern_mat[, i] != 0]
    })
    names(pSet1) <- colnames(kpattern_mat)
    
    # Extract gene sets from cluster_assignments (pSet2)
    if (any(rownames(cluster_assignments) %in% rownames(target_expression))) {
      genes <- rownames(cluster_assignments)
      clusters <- cluster_assignments[[1]]
    } else if (ncol(cluster_assignments) >= 2) {
      genes <- as.character(cluster_assignments[[1]])
      clusters <- cluster_assignments[[2]]
    } else {
      genes <- rownames(cluster_assignments)
      clusters <- cluster_assignments[[1]]
    }
    pSet2 <- split(genes, clusters)
    
    # 5. Execute Documented Workflow Stage 2: intersectoR
    overlap_results <- intersectoR(pSet1 = pSet1, pSet2 = pSet2, pval = 0.05, full = FALSE, k = NULL)
    overlap_results_full <- intersectoR(pSet1 = pSet1, pSet2 = pSet2, pval = 0.05, full = TRUE, k = NULL)
    
    # 6. Save Outputs
    saveRDS(kpattern, "kpattern.rds")
    write.csv(kpattern_mat, "kpattern_matrix.csv", row.names = TRUE)
    write.csv(as.matrix(overlap_results), "overlap_summary.csv", row.names = TRUE)
    saveRDS(overlap_results_full, "overlap_results_full.rds")
    
    # Generate a PDF plot of the kpattern weights
    pdf("kpattern_heatmap.pdf")
    if (requireNamespace("gplots", quietly = TRUE)) {
      gplots::heatmap.2(kpattern_mat, trace = "none", col = gplots::bluered(100), margins = c(10, 10), main = "Cluster Patterns")
    } else {
      heatmap(kpattern_mat, main = "Cluster Patterns")
    }
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_PROJECTR_CLUSTERING_PROJECTION":',
        paste0('    projectR: ', as.character(packageVersion('projectR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clustering_projection.csv versions.yml
    """
}

workflow BIOC_PROJECTR_CLUSTERING_PROJECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ target_expression.csv, cluster_assignments.csv ] ]

    main:
    BIOC_PROJECTR_CLUSTERING_PROJECTION(ch_input)

    emit:
    tables   = BIOC_PROJECTR_CLUSTERING_PROJECTION.out.tables
    plots    = BIOC_PROJECTR_CLUSTERING_PROJECTION.out.plots
    objects  = BIOC_PROJECTR_CLUSTERING_PROJECTION.out.objects
    versions = BIOC_PROJECTR_CLUSTERING_PROJECTION.out.versions
}
