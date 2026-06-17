#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ConsensusClusterPlus — standard_consensus_clustering
// Perform consensus clustering on a gene expression matrix to identify stable sample clusters and calculate cluster/item consensus.
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-consensusclusterplus:1.74.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ConsensusClusterPlus
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter features by variability using median absolute deviation (mad)
//  * 2. [Core Analysis] Median-center the features using sweep
//  * 3. [Core Analysis] Run consensus clustering using ConsensusClusterPlus
//  * 4. [Core Analysis] Calculate cluster and item consensus using calcICL

nextflow.enable.dsl = 2

process BIOC_CONSENSUSCLUSTERPLUS_STANDARD_CONSENSUS_CLUSTERING {
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
    
    # Check for required input file
    if (!file.exists("expression_matrix.csv")) {
      stop("Error: 'expression_matrix.csv' not found in the working directory.")
    }
    
    # 1. Read the user input expression matrix
    # Expecting a CSV with gene/feature IDs in the first column and sample IDs as headers
    d = as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    
    # 2. Filter features by variability using median absolute deviation (mad)
    mads = apply(d, 1, mad)
    # Handle cases where the input matrix has fewer than 5000 features
    n_features = min(5000, nrow(d))
    d = d[rev(order(mads))[1:n_features], ]
    
    # 3. Median-center the features using sweep
    d = sweep(d, 1, apply(d, 1, median, na.rm = TRUE))
    
    # 4. Run consensus clustering using ConsensusClusterPlus
    library(ConsensusClusterPlus)
    
    # Define output directory for plots and tables
    title = "consensus_clustering_plots"
    if (!dir.exists(title)) {
      dir.create(title, recursive = TRUE)
    }
    
    results = ConsensusClusterPlus(
      d,
      maxK = 6,
      reps = 50,
      pItem = 0.8,
      pFeature = 1,
      title = title,
      clusterAlg = "hc",
      distance = "pearson",
      seed = 1262118388.71279,
      plot = "png"
    )
    
    # 5. Calculate cluster and item consensus using calcICL
    icl = calcICL(results, title = title, plot = "png")
    
    # 6. Save meaningful results to output files
    # Save R objects for downstream analysis
    saveRDS(results, file = "consensus_results.rds")
    saveRDS(icl, file = "consensus_icl.rds")
    
    # Save cluster consensus and item consensus tables
    write.csv(icl[["clusterConsensus"]], file = "cluster_consensus.csv", row.names = FALSE)
    write.csv(icl[["itemConsensus"]], file = "item_consensus.csv", row.names = FALSE)
    
    # Save sample cluster assignments for each evaluated K
    for (k in 2:6) {
      if (!is.null(results[[k]])) {
        class_assignment = results[[k]][["consensusClass"]]
        class_df = data.frame(
          Sample = names(class_assignment),
          Cluster = class_assignment,
          stringsAsFactors = FALSE
        )
        write.csv(class_df, file = paste0("consensus_class_k", k, ".csv"), row.names = FALSE)
      }
    }

    writeLines(c(
        '"BIOC_CONSENSUSCLUSTERPLUS_STANDARD_CONSENSUS_CLUSTERING":',
        paste0('    ConsensusClusterPlus: ', as.character(packageVersion('ConsensusClusterPlus')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_consensus_clustering.csv versions.yml
    """
}

workflow BIOC_CONSENSUSCLUSTERPLUS_STANDARD_CONSENSUS_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_CONSENSUSCLUSTERPLUS_STANDARD_CONSENSUS_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_CONSENSUSCLUSTERPLUS_STANDARD_CONSENSUS_CLUSTERING.out.tables
    plots    = BIOC_CONSENSUSCLUSTERPLUS_STANDARD_CONSENSUS_CLUSTERING.out.plots
    objects  = BIOC_CONSENSUSCLUSTERPLUS_STANDARD_CONSENSUS_CLUSTERING.out.objects
    versions = BIOC_CONSENSUSCLUSTERPLUS_STANDARD_CONSENSUS_CLUSTERING.out.versions
}
