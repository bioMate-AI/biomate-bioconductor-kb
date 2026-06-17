#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioCor — merge_similarity_sources
// Combine similarity matrices calculated from different databases (e.g., KEGG and Reactome) using weighted functions.
// Input: genesKegg, genesReact
// Container: quay.io/biocontainers/bioconductor-biocor:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BioCor
// Visualizations: image plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate similarity matrices for each database using mgeneSim
//  * 2. [Core Analysis] Combine the matrices into a list
//  * 3. [Core Analysis] Merge them using similarities with a combining function like weighted.sum or weighted.prod and specified weights

nextflow.enable.dsl = 2

process BIOC_BIOCOR_MERGE_SIMILARITY_SOURCES {
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
    .bm_deps <- c("BioCor")
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
        library(BioCor)
        
        # -----------------------------------------------------------------------------
        # Stage 0: Read User Input Files
        # -----------------------------------------------------------------------------
        # The pipeline expects 'genesKegg' and 'genesReact' to be in the working directory.
        # Since these are R list objects, we read them using readRDS.
        
        if (file.exists("genesKegg")) {
          genesKegg <- readRDS("genesKegg")
        } else if (file.exists("genesKegg.rds")) {
          genesKegg <- readRDS("genesKegg.rds")
        } else {
          stop("Required input file 'genesKegg' or 'genesKegg.rds' not found in the working directory.")
        }
        
        if (file.exists("genesReact")) {
          genesReact <- readRDS("genesReact")
        } else if (file.exists("genesReact.rds")) {
          genesReact <- readRDS("genesReact.rds")
        } else {
          stop("Required input file 'genesReact' or 'genesReact.rds' not found in the working directory.")
        }
        
        # Dynamically extract common genes from the user-provided input lists
        common_genes <- intersect(names(genesKegg), names(genesReact))
        
        if (length(common_genes) < 2) {
          stop("At least two common genes are required between genesKegg and genesReact to perform similarity analysis.")
        }
        
        # -----------------------------------------------------------------------------
        # Stage 1: Calculate similarity matrices for each database using mgeneSim
        # -----------------------------------------------------------------------------
        kegg <- mgeneSim(common_genes, genesKegg)
        react <- mgeneSim(common_genes, genesReact)
        
        # -----------------------------------------------------------------------------
        # Stage 2: Combine the matrices into a list and perform weighted sum on elements
        # -----------------------------------------------------------------------------
        g1 <- common_genes[1]
        g2 <- common_genes[2]
        
        ## We can sum it adding a weight to each origin
        single_w_sum <- weighted.sum(c(kegg[g1, g2], react[g1, g2]), w = c(0.3, 0.7))
        
        ## Or if we want to perform for all the matrix
        ## A list of matrices to merge
        sim <- list("kegg" = kegg, "react" = react)
        
        # -----------------------------------------------------------------------------
        # Stage 3: Merge them using similarities with various combining functions
        # -----------------------------------------------------------------------------
        sim_weighted_sum  <- similarities(sim, weighted.sum, w = c(0.3, 0.7))
        sim_weighted_prod <- similarities(sim, weighted.prod, w = c(0.3, 0.7))
        sim_prod          <- similarities(sim, prod)
        sim_mean          <- similarities(sim, mean)
        
        # -----------------------------------------------------------------------------
        # Stage 4: Write Named Output Files
        # -----------------------------------------------------------------------------
        # Save RDS objects
        saveRDS(kegg, "kegg_similarity.rds")
        saveRDS(react, "react_similarity.rds")
        saveRDS(sim_weighted_sum, "similarity_weighted_sum.rds")
        saveRDS(sim_weighted_prod, "similarity_weighted_prod.rds")
        saveRDS(sim_prod, "similarity_prod.rds")
        saveRDS(sim_mean, "similarity_mean.rds")
        
        # Save CSV tables
        write.csv(as.data.frame(kegg), "kegg_similarity.csv", row.names = TRUE)
        write.csv(as.data.frame(react), "react_similarity.csv", row.names = TRUE)
        write.csv(as.data.frame(sim_weighted_sum), "similarity_weighted_sum.csv", row.names = TRUE)
        write.csv(as.data.frame(sim_weighted_prod), "similarity_weighted_prod.csv", row.names = TRUE)
        write.csv(as.data.frame(sim_prod), "similarity_prod.csv", row.names = TRUE)
        write.csv(as.data.frame(sim_mean), "similarity_mean.csv", row.names = TRUE)
        
        # Save single value output
        writeLines(as.character(single_w_sum), "single_weighted_sum_value.txt")
        
        # Generate PDF plots of the similarity matrices
        pdf("similarity_matrices_heatmaps.pdf", width = 10, height = 8)
        par(mfrow = c(2, 3))
        image(kegg, main = "KEGG Similarity", axes = FALSE)
        image(react, main = "Reactome Similarity", axes = FALSE)
        image(sim_weighted_sum, main = "Weighted Sum (0.3 KEGG, 0.7 React)", axes = FALSE)
        image(sim_weighted_prod, main = "Weighted Prod (0.3 KEGG, 0.7 React)", axes = FALSE)
        image(sim_prod, main = "Product Similarity", axes = FALSE)
        image(sim_mean, main = "Mean Similarity", axes = FALSE)
        dev.off()
        
        message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_BIOCOR_MERGE_SIMILARITY_SOURCES":',
        paste0('    BioCor: ', as.character(packageVersion('BioCor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_merge_similarity_sources.csv versions.yml
    """
}

workflow BIOC_BIOCOR_MERGE_SIMILARITY_SOURCES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genesKegg, genesReact ] ]

    main:
    BIOC_BIOCOR_MERGE_SIMILARITY_SOURCES(ch_input)

    emit:
    tables   = BIOC_BIOCOR_MERGE_SIMILARITY_SOURCES.out.tables
    plots    = BIOC_BIOCOR_MERGE_SIMILARITY_SOURCES.out.plots
    objects  = BIOC_BIOCOR_MERGE_SIMILARITY_SOURCES.out.objects
    versions = BIOC_BIOCOR_MERGE_SIMILARITY_SOURCES.out.versions
}
