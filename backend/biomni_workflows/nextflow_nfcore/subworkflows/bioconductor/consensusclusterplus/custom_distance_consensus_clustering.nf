#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ConsensusClusterPlus — custom_distance_consensus_clustering
// Perform consensus clustering using a pre-computed custom distance matrix to reduce computation time on large datasets.
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-consensusclusterplus:1.74.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ConsensusClusterPlus
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute a custom distance matrix from the expression data
//  * 2. [Core Analysis] Run consensus clustering using ConsensusClusterPlus with the pre-computed distance matrix

nextflow.enable.dsl = 2

process BIOC_CONSENSUSCLUSTERPLUS_CUSTOM_DISTANCE_CONSENSUS_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("ConsensusClusterPlus")
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
    library(ConsensusClusterPlus)
    
    # ==========================================
    # 1. Read User Input
    # ==========================================
    # The pipeline expects 'expression_matrix.csv' in the working directory.
    # Columns represent samples (items) and rows represent genes (features).
    input_file <- "expression_matrix.csv"
    
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the expression matrix
    expression_data <- read.csv(input_file, row.names = 1, check.names = FALSE)
    d <- as.matrix(expression_data)
    
    # ==========================================
    # 2. Compute Custom Distance Matrix
    # ==========================================
    # Compute a custom distance matrix using Pearson correlation to reduce computation time
    dt = as.dist(1-cor(d,method="pearson"))
    
    # ==========================================
    # 3. Run Consensus Clustering
    # ==========================================
    # Execute ConsensusClusterPlus using the pre-computed distance matrix.
    # This matches the documented workflow exactly.
    results = ConsensusClusterPlus(dt,maxK=4,reps=100,pItem=0.8,pFeature=1,title="example2",distance="pearson",clusterAlg="hc")
    
    # ==========================================
    # 4. Save Meaningful Results and Outputs
    # ==========================================
    # Save the main consensus clustering results object
    saveRDS(results, file = "consensus_cluster_results.rds")
    
    # Calculate and save Cluster Consensus and Item Consensus (ICL)
    icl = calcICL(results, title="example2", plot="pdf")
    saveRDS(icl, file = "icl_results.rds")
    
    # Export consensus classes and consensus matrices for each evaluated K (K=2 to maxK=4)
    for (k in 2:4) {
      # Extract and save sample classifications
      if (!is.null(results[[k]][["consensusClass"]])) {
        class_vector <- results[[k]][["consensusClass"]]
        class_df <- data.frame(
          Sample = names(class_vector),
          Cluster = class_vector,
          stringsAsFactors = FALSE
        )
        write.csv(class_df, file = paste0("consensus_class_k", k, ".csv"), row.names = FALSE)
      }
      
      # Extract and save consensus matrix
      if (!is.null(results[[k]][["consensusMatrix"]])) {
        consensus_mat <- results[[k]][["consensusMatrix"]]
        # Assign sample names to rows and columns for clarity
        rownames(consensus_mat) <- colnames(d)
        colnames(consensus_mat) <- colnames(d)
        write.csv(consensus_mat, file = paste0("consensus_matrix_k", k, ".csv"))
      }
    }
    
    # Export ICL results to CSV tables
    if (!is.null(icl[["clusterConsensus"]])) {
      write.csv(icl[["clusterConsensus"]], file = "cluster_consensus.csv", row.names = FALSE)
    }
    
    if (!is.null(icl[["itemConsensus"]])) {
      write.csv(icl[["itemConsensus"]], file = "item_consensus.csv", row.names = FALSE)
    }
    
    cat("Pipeline completed successfully. Outputs saved to 'example2/' directory and current working directory.\n")

    writeLines(c(
        '"BIOC_CONSENSUSCLUSTERPLUS_CUSTOM_DISTANCE_CONSENSUS_CLUSTERING":',
        paste0('    ConsensusClusterPlus: ', as.character(packageVersion('ConsensusClusterPlus')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_distance_consensus_clustering.csv versions.yml
    """
}

workflow BIOC_CONSENSUSCLUSTERPLUS_CUSTOM_DISTANCE_CONSENSUS_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_CONSENSUSCLUSTERPLUS_CUSTOM_DISTANCE_CONSENSUS_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_CONSENSUSCLUSTERPLUS_CUSTOM_DISTANCE_CONSENSUS_CLUSTERING.out.tables
    plots    = BIOC_CONSENSUSCLUSTERPLUS_CUSTOM_DISTANCE_CONSENSUS_CLUSTERING.out.plots
    objects  = BIOC_CONSENSUSCLUSTERPLUS_CUSTOM_DISTANCE_CONSENSUS_CLUSTERING.out.objects
    versions = BIOC_CONSENSUSCLUSTERPLUS_CUSTOM_DISTANCE_CONSENSUS_CLUSTERING.out.versions
}
