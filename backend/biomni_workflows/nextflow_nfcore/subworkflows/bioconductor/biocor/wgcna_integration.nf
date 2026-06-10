#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioCor — wgcna_integration
// Combine gene expression correlation with functional pathway similarity to identify functionally-guided co-expression modules.
// Input: expr, sim
// Container: quay.io/biocontainers/bioconductor-biocor:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BioCor, dynamicTreeCut
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate expression correlation matrix using WGCNA::cor
//  * 2. [Core Analysis] Combine expression correlation and functional similarity matrices using similarities
//  * 3. [Core Analysis] Estimate soft threshold using pickSoftThreshold.fromSimilarity
//  * 4. [Core Analysis] Calculate adjacency matrix using adjacency.fromSimilarity
//  * 5. [Core Analysis] Calculate TOM similarity and dissimilarity
//  * 6. [Core Analysis] Perform hierarchical clustering and identify modules using cutreeHybrid

nextflow.enable.dsl = 2

process BIOC_BIOCOR_WGCNA_INTEGRATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(BioCor)
    library(WGCNA)
    library(dynamicTreeCut)
    
    # Enable multi-threading for WGCNA if available
    allowWGCNAThreads()
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read expression matrix (samples in rows, genes in columns)
    if (file.exists("expr.rds")) {
      expr <- readRDS("expr.rds")
    } else if (file.exists("expr.csv")) {
      expr <- as.matrix(read.csv("expr.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Required input file 'expr.rds' or 'expr.csv' not found in the working directory.")
    }
    
    # Read functional similarity matrices (list of matrices)
    if (file.exists("sim.rds")) {
      sim <- readRDS("sim.rds")
    } else if (file.exists("sim.csv")) {
      # Fallback if similarity is provided as a single CSV matrix
      sim_matrix <- as.matrix(read.csv("sim.csv", row.names = 1, check.names = FALSE))
      sim <- list(functional = sim_matrix)
    } else {
      stop("Required input file 'sim.rds' or 'sim.csv' not found in the working directory.")
    }
    
    # Ensure expression matrix is numeric
    if (!is.numeric(expr)) {
      expr <- matrix(as.numeric(expr), nrow = nrow(expr), ncol = ncol(expr),
                     dimnames = list(rownames(expr), colnames(expr)))
    }
    
    # ==========================================
    # 2. Documented Workflow Execution
    # ==========================================
    
    ## Calculate expression correlation matrix
    expr.sim <- WGCNA::cor(expr) # or bicor
    
    ## Combine the similarities
    similarity <- similarities(c(list(exp = expr.sim), sim), mean, na.rm = TRUE)
    
    ## Choose the softThreshold
    pSFT <- pickSoftThreshold.fromSimilarity(similarity)
    
    # Robustness check: If power estimate is NA/NULL, default to a standard soft threshold (e.g., 6)
    if (is.null(pSFT\$powerEstimate) || is.na(pSFT\$powerEstimate)) {
      message("Soft threshold power estimate was NA/NULL. Defaulting to power = 6.")
      pSFT\$powerEstimate <- 6
    }
    
    ## Or any other function we want
    adjacency <- adjacency.fromSimilarity(similarity, power = pSFT\$powerEstimate)
    
    ## Once we have the similarities we can calculate the TOM with TOM
    TOM <- TOMsimilarity(adjacency) ## Requires adjacencies despite its name
    dissTOM <- 1 - TOM
    geneTree <- hclust(as.dist(dissTOM), method = "average")
    
    ## We can use a clustering tool to group the genes
    dynamicMods <- cutreeHybrid(dendro = geneTree, distM = dissTOM,
                                deepSplit = 2, pamRespectsDendro = FALSE,
                                minClusterSize = 30)
    moduleColors <- labels2colors(dynamicMods\$labels)
    
    # ==========================================
    # 3. Save Outputs and Results
    # ==========================================
    
    # Save module assignments as a CSV table
    results_df <- data.frame(
      Gene = colnames(expr),
      ModuleLabel = dynamicMods\$labels,
      ModuleColor = moduleColors,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "module_assignments.csv", row.names = FALSE)
    
    # Save the network matrices as an RDS object
    network_data <- list(
      combined_similarity = similarity,
      adjacency = adjacency,
      TOM = TOM,
      geneTree = geneTree,
      powerEstimate = pSFT\$powerEstimate
    )
    saveRDS(network_data, "wgcna_integration_results.rds")
    
    # Plot and save the gene dendrogram with module colors
    pdf("gene_dendrogram.pdf", width = 12, height = 8)
    WGCNA::plotDendroAndColors(
      dendro = geneTree,
      colors = moduleColors,
      groupLabels = "Modules",
      dendroLabels = FALSE,
      hang = 0.03,
      addGuide = TRUE,
      guideHang = 0.05,
      main = "Gene Dendrogram and Module Colors (BioCor + WGCNA)"
    )
    dev.off()
    
    message("Workflow completed successfully. Outputs written to 'module_assignments.csv', 'wgcna_integration_results.rds', and 'gene_dendrogram.pdf'.")

    writeLines(c(
        '"BIOC_BIOCOR_WGCNA_INTEGRATION":',
        paste0('    BioCor: ', as.character(packageVersion('BioCor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_wgcna_integration.csv versions.yml
    """
}

workflow BIOC_BIOCOR_WGCNA_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expr, sim ] ]

    main:
    BIOC_BIOCOR_WGCNA_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_BIOCOR_WGCNA_INTEGRATION.out.tables
    plots    = BIOC_BIOCOR_WGCNA_INTEGRATION.out.plots
    objects  = BIOC_BIOCOR_WGCNA_INTEGRATION.out.objects
    versions = BIOC_BIOCOR_WGCNA_INTEGRATION.out.versions
}
