#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: eiR — compound_clustering
// Perform fast Jarvis-Patrick clustering on the embedded compound database.
// Input: runId
// Container: quay.io/biocontainers/bioconductor-eir:1.50.0--r45ha27e39d_0
// R packages: eiR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EIR_COMPOUND_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-eir:1.50.0--r45ha27e39d_0"

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
    .bm_deps <- c("eiR")
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
    library(eiR)
    
    # Read user input: runId
    runId_file <- "runId"
    if (!file.exists(runId_file) && file.exists("runId.txt")) {
      runId_file <- "runId.txt"
    }
    if (!file.exists(runId_file)) {
      stop("Required input file 'runId' or 'runId.txt' not found in the working directory.")
    }
    
    runId <- as.integer(readLines(runId_file, n = 1, warn = FALSE))
    
    # Perform Jarvis-Patrick clustering on the embedded compound database
    clustering <- eiCluster(runId,K=5,minNbrs=2,cutoff=0.5)
    
    # View the clustering results
    cluster_results <- byCluster(clustering)
    
    # Save outputs
    saveRDS(clustering, "clustering_object.rds")
    saveRDS(cluster_results, "by_cluster_list.rds")
    
    # Format and save as CSV
    if (length(cluster_results) > 0) {
      cluster_names <- names(cluster_results)
      if (is.null(cluster_names)) {
        cluster_names <- seq_along(cluster_results)
      }
      cluster_df <- data.frame(
        Cluster_ID = rep(cluster_names, lengths(cluster_results)),
        Compound_ID = unlist(cluster_results),
        stringsAsFactors = FALSE
      )
      write.csv(cluster_df, "clustering_results.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Cluster_ID = character(), Compound_ID = character()), 
                "clustering_results.csv", row.names = FALSE)
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_EIR_COMPOUND_CLUSTERING":
        eiR: \$(Rscript -e 'cat(as.character(packageVersion("eiR")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compound_clustering.csv versions.yml
    """
}

workflow BIOC_EIR_COMPOUND_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ runId ] ]

    main:
    BIOC_EIR_COMPOUND_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_EIR_COMPOUND_CLUSTERING.out.tables
    plots    = BIOC_EIR_COMPOUND_CLUSTERING.out.plots
    objects  = BIOC_EIR_COMPOUND_CLUSTERING.out.objects
    versions = BIOC_EIR_COMPOUND_CLUSTERING.out.versions
}
