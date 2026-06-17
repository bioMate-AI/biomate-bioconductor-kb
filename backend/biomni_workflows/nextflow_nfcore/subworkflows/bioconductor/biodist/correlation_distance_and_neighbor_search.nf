#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bioDist — correlation_distance_and_neighbor_search
// Calculate correlation-based distances (Spearman's rho and Kendall's tau) between genes and find the nearest neighbors for a specific gene.
// Input: expression_set.RData
// Container: quay.io/biocontainers/bioconductor-biodist:1.82.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, bioDist
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Save distance matrices as CSV
//  * 2. [Core Analysis] Save nearest neighbors as CSV
//  * 3. [Core Analysis] Save distance objects as RDS
//  * 4. [Core Analysis] Generate a PDF plot comparing the distributions of the

nextflow.enable.dsl = 2

process BIOC_BIODIST_CORRELATION_DISTANCE_AND_NEIGHBOR_SEARCH {
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
    .bm_deps <- c("bioDist", "Biobase")
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
        library(bioDist)
        library(Biobase)
        
        # Read the user input file
        input_file <- "expression_set.RData"
        if (!file.exists(input_file)) {
          stop(paste("Required input file missing:", input_file))
        }
        
        # Load the RData file into a temporary environment to locate the ExpressionSet object
        temp_env <- new.env()
        load(input_file, envir = temp_env)
        
        # Find the ExpressionSet object in the loaded environment
        es_name <- NULL
        for (name in ls(temp_env)) {
          if (inherits(temp_env[[name]], "ExpressionSet")) {
            es_name <- name
            break
          }
        }
        
        if (is.null(es_name)) {
          stop("No ExpressionSet object found in the loaded RData file.")
        }
        
        # Assign to the variable name expected by the documented code
        sample.ExpressionSet <- temp_env[[es_name]]
        
        # Ensure the ExpressionSet has enough features to find 3 neighbors
        if (nrow(sample.ExpressionSet) < 4) {
          stop("The input ExpressionSet must have at least 4 features.")
        }
        
        # === DOCUMENTED CODE ===
        n_features <- nrow(sample.ExpressionSet)
        start_idx <- max(1, n_features - 99)
        eS = sample.ExpressionSet[start_idx:n_features,]
        tauD = tau.dist(eS, sample=FALSE)
        sp = spearman.dist(eS, sample=FALSE)
        f1 = featureNames(eS)[1]
        neighbors = closest.top(f1, sp, 3)
        # === END DOCUMENTED CODE ===
        
        # Print the closest neighbors to the console
        cat("Top 3 closest neighbors for gene", f1, ":\n")
        print(neighbors)
        
        # Save meaningful results to output files
        # --- Save distance matrices as CSV ---
        tau_matrix <- as.matrix(tauD)
        sp_matrix <- as.matrix(sp)
        
        write.csv(tau_matrix, "tau_distance_matrix.csv", row.names = TRUE)
        write.csv(sp_matrix, "spearman_distance_matrix.csv", row.names = TRUE)
        
        # --- Save nearest neighbors as CSV ---
        neighbors_df <- data.frame(
          Query_Gene = rep(f1, length(neighbors)),
          Neighbor_Gene = neighbors,
          Rank = seq_along(neighbors)
        )
        write.csv(neighbors_df, "closest_neighbors.csv", row.names = FALSE)
        
        # --- Save distance objects as RDS ---
        saveRDS(tauD, "tau_distance.rds")
        saveRDS(sp, "spearman_distance.rds")
        
        # --- Generate a PDF plot comparing the distributions of the ---
        pdf("distance_distributions.pdf", width = 10, height = 5)
        par(mfrow = c(1, 2))
        hist(as.vector(tauD), 
             main = "Distribution of Kendall's Tau Distances",
             xlab = "Distance", 
             col = "skyblue", 
             border = "white")
        hist(as.vector(sp), 
             main = "Distribution of Spearman's Rho Distances",
             xlab = "Distance", 
             col = "salmon", 
             border = "white")
        dev.off()
        
        cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_BIODIST_CORRELATION_DISTANCE_AND_NEIGHBOR_SEARCH":',
        paste0('    bioDist: ', as.character(packageVersion('bioDist')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_correlation_distance_and_neighbor_search.csv versions.yml
    """
}

workflow BIOC_BIODIST_CORRELATION_DISTANCE_AND_NEIGHBOR_SEARCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_set.RData ] ]

    main:
    BIOC_BIODIST_CORRELATION_DISTANCE_AND_NEIGHBOR_SEARCH(ch_input)

    emit:
    tables   = BIOC_BIODIST_CORRELATION_DISTANCE_AND_NEIGHBOR_SEARCH.out.tables
    plots    = BIOC_BIODIST_CORRELATION_DISTANCE_AND_NEIGHBOR_SEARCH.out.plots
    objects  = BIOC_BIODIST_CORRELATION_DISTANCE_AND_NEIGHBOR_SEARCH.out.objects
    versions = BIOC_BIODIST_CORRELATION_DISTANCE_AND_NEIGHBOR_SEARCH.out.versions
}
