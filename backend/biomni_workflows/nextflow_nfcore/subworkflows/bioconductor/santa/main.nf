#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SANTA — network_association_analysis
// Measure the clustering of a phenotype (binary or continuous vertex weights) across a network to quantify their strength of association.
// Input: network.gml, phenotype_weights.csv
// Container: quay.io/biocontainers/bioconductor-santa:2.46.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SANTA, igraph
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute pairwise vertex distances across the network using DistGraph
//  * 2. [Core Analysis] Bin the distances into discrete intervals using BinGraph to optimize performance
//  * 3. [Core Analysis] Assign the phenotype weights to the network vertices
//  * 4. [Core Analysis] Run Knet to calculate the clustering significance (p-value) via permutation testing

nextflow.enable.dsl = 2

process BIOC_SANTA_NETWORK_ASSOCIATION_ANALYSIS {
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
    .bm_deps <- c("SANTA", "igraph")
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
    library(SANTA)
    library(igraph)
    
    # Define input file paths
    network_file <- "network.gml"
    phenotype_file <- "phenotype_weights.csv"
    
    # Check if input files exist
    if (!file.exists(network_file)) {
      stop(paste("Error: Input network file not found:", network_file))
    }
    if (!file.exists(phenotype_file)) {
      stop(paste("Error: Input phenotype weights file not found:", phenotype_file))
    }
    
    # Load the network
    g <- read_graph(network_file, format="gml")
    
    # Load the phenotype weights
    pheno_df <- read.csv(phenotype_file, stringsAsFactors=FALSE)
    
    # Identify columns: assume 1st column is gene/node name, 2nd column is weight
    gene_col <- colnames(pheno_df)[1]
    weight_col <- colnames(pheno_df)[2]
    
    # Map weights to network vertices
    v_names <- V(g)\$name
    if (is.null(v_names)) {
      stop("Error: Network vertices do not have a 'name' attribute for mapping phenotype weights.")
    }
    
    # Create a mapping vector
    weight_map <- pheno_df[[weight_col]]
    names(weight_map) <- as.character(pheno_df[[gene_col]])
    
    # Assign weights to the vertex attribute "hits", filling missing ones with NA
    vertex_weights <- weight_map[v_names]
    g <- set.vertex.attribute(g, name="hits", value=vertex_weights)
    
    # Define distance method
    dist.method <- "shortest.paths"
    
    # 1. Compute pairwise vertex distances across the network using DistGraph
    D <- DistGraph(g, dist.method=dist.method, verbose=FALSE)
    
    # 2. Bin the distances into discrete intervals using BinGraph to optimize performance
    B <- BinGraph(D, verbose=FALSE)
    
    # 3 & 4. Run Knet to calculate the clustering significance (p-value) via permutation testing
    # Using nperm=100 as shown in the documented code (1000+ is recommended for publication-grade accuracy)
    knet_res <- Knet(g, nperm=100, dist.method=dist.method, vertex.attr="hits", B=B, verbose=FALSE)
    
    # Save the complete Knet result object
    saveRDS(knet_res, "knet_result.rds")
    
    # Create and save a summary table of the results
    results_df <- data.frame(
      observed_AUK = ifelse(!is.null(knet_res\$observed), knet_res\$observed, NA),
      p_value = ifelse(!is.null(knet_res\$pval), knet_res\$pval, NA),
      mean_perm_AUK = ifelse(!is.null(knet_res\$mean), knet_res\$mean, NA),
      sd_perm_AUK = ifelse(!is.null(knet_res\$sd), knet_res\$sd, NA)
    )
    write.csv(results_df, "knet_results.csv", row.names=FALSE)
    
    # Generate and save the Knet plot
    tryCatch({
      pdf("knet_plot.pdf")
      plot(knet_res)
      dev.off()
    }, error = function(e) {
      warning("Could not generate Knet plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_SANTA_NETWORK_ASSOCIATION_ANALYSIS":',
        paste0('    SANTA: ', as.character(packageVersion('SANTA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_network_association_analysis.csv versions.yml
    """
}

workflow BIOC_SANTA_NETWORK_ASSOCIATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ network.gml, phenotype_weights.csv ] ]

    main:
    BIOC_SANTA_NETWORK_ASSOCIATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SANTA_NETWORK_ASSOCIATION_ANALYSIS.out.tables
    plots    = BIOC_SANTA_NETWORK_ASSOCIATION_ANALYSIS.out.plots
    objects  = BIOC_SANTA_NETWORK_ASSOCIATION_ANALYSIS.out.objects
    versions = BIOC_SANTA_NETWORK_ASSOCIATION_ANALYSIS.out.versions
}
