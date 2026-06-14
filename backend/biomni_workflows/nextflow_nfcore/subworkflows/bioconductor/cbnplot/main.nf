#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CBNplot — gene_level_bayesian_network
// Infer and plot a Bayesian network of genes within a specific enriched pathway using expression data.
// Input: enrichResult.rds, expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-cbnplot:1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CBNplot, bnlearn, igraph
// Visualizations: pathway diagram
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Visualize the gene-level Bayesian network for a specific pathway using bngeneplot
//  * 2. [Core Analysis] Extract the underlying network structure, strength, and direction by setting returnNet=TRUE
//  * 3. [Core Analysis] Convert the averaged network to an igraph object for centrality analysis
//  * 4. [Visualization & Output] Customize the gene network visualization using bngeneplotCustom

nextflow.enable.dsl = 2

process BIOC_CBNPLOT_GENE_LEVEL_BAYESIAN_NETWORK {
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
    .bm_deps <- c("CBNplot", "bnlearn", "igraph")
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
        library(CBNplot)
        library(bnlearn)
        library(igraph)
        
        # 1. Load User Inputs
        # Read the enrichment analysis result object (e.g., clusterProfiler or ReactomePA result)
        pway <- readRDS("enrichResult.rds")
        
        # Read the normalized gene expression matrix (genes as rows, samples as columns)
        counts <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
        
        # 2. Visualize the gene-level Bayesian network for the first pathway
        pdf("bngeneplot_pathway1.pdf", width = 10, height = 10)
        print(bngeneplot(results = pway, exp = counts, pathNum = 1, expRow="ENTREZID"))
        dev.off()
        
        # 3. Extract the underlying network structure, strength, and direction
        ret <- bngeneplot(results = pway, exp = counts, pathNum = 1, returnNet=TRUE, expRow="ENTREZID")
        
        # Save the network strength and structure data frame
        write.csv(ret\$str, "network_strength.csv", row.names = FALSE)
        saveRDS(ret, "network_results.rds")
        
        # 4. Convert the averaged network to an igraph object and perform centrality analysis
        g <- bnlearn::as.igraph(ret\$av)
        saveRDS(g, "network_igraph.rds")
        
        # Calculate eigenvector centrality
        ev_centrality <- tryCatch({
          igraph::evcent(g)\$vector
        }, error = function(e) {
          # Fallback to eigen_centrality if evcent is completely removed/fails
          igraph::eigen_centrality(g)\$vector
        })
        
        # Save centrality metrics
        centrality_df <- data.frame(
          Gene = names(ev_centrality),
          EigenvectorCentrality = ev_centrality,
          stringsAsFactors = FALSE
        )
        write.csv(centrality_df, "gene_centrality.csv", row.names = FALSE)
        
        # 5. Customize the gene network visualization
        pdf("bngeneplot_custom.pdf", width = 10, height = 10)
        print(bngeneplotCustom(results = pway, exp = counts, expRow="ENTREZID",
                         pathNum=1, fontFamily="sans", glowEdgeNum=NULL, hub=1))
        dev.off()

    writeLines(c(
        '"BIOC_CBNPLOT_GENE_LEVEL_BAYESIAN_NETWORK":',
        paste0('    CBNplot: ', as.character(packageVersion('CBNplot')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_level_bayesian_network.csv versions.yml
    """
}

workflow BIOC_CBNPLOT_GENE_LEVEL_BAYESIAN_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ enrichResult.rds, expression_matrix.csv ] ]

    main:
    BIOC_CBNPLOT_GENE_LEVEL_BAYESIAN_NETWORK(ch_input)

    emit:
    tables   = BIOC_CBNPLOT_GENE_LEVEL_BAYESIAN_NETWORK.out.tables
    plots    = BIOC_CBNPLOT_GENE_LEVEL_BAYESIAN_NETWORK.out.plots
    objects  = BIOC_CBNPLOT_GENE_LEVEL_BAYESIAN_NETWORK.out.objects
    versions = BIOC_CBNPLOT_GENE_LEVEL_BAYESIAN_NETWORK.out.versions
}
