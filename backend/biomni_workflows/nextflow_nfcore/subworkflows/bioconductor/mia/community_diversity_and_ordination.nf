#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mia — community_diversity_and_ordination
// Calculate alpha diversity indices and perform beta diversity ordination (MDS/PCoA) on microbiome profiles.
// Input: GlobalPatterns.RDS
// Container: quay.io/biocontainers/bioconductor-mia:1.18.0--r45ha27e39d_0
// R packages: ggplot2, mia, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, mia, scater
// Visualizations: ordination plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read the input TreeSummarizedExperiment object
//  * 2. [Core Analysis] Estimate sample-wise alpha diversity (Shannon index)
//  * 3. [Core Analysis] Agglomerate taxonomic ranks
//  * 4. [Core Analysis] Perform Multidimensional Scaling (MDS/PCoA) ordination on
//  * 5. [Core Analysis] Save meaningful results to output files

nextflow.enable.dsl = 2

process BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("ggplot2", "mia", "scater", "SummarizedExperiment")
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
    library(mia)
    library(SummarizedExperiment)
    library(scater)
    library(ggplot2)
    
    # --- Read the input TreeSummarizedExperiment object ---
    # The pipeline reads EXACTLY the declared user input file from the working directory.
    tse <- readRDS("GlobalPatterns.RDS")
    
    # --- Estimate sample-wise alpha diversity (Shannon index) ---
    # This appends the results directly to the sample metadata (colData).
    tse <- addAlpha(tse, index = "shannon")
    
    # --- Agglomerate taxonomic ranks ---
    # This creates alternative experiments for each taxonomic rank, including "Genus".
    tse <- agglomerateByRanks(tse)
    
    # --- Perform Multidimensional Scaling (MDS/PCoA) ordination on ---
    # This calculates inter-sample beta diversity dissimilarity (Bray-Curtis) and stores the reduced dimensions.
    altExp(tse, "Genus") <- runMDS(
        altExp(tse, "Genus"), 
        FUN = getDissimilarity,
        method = "bray",
        name = "BrayCurtis", 
        ncomponents = 5, 
        assay.type = "counts", 
        keep_dist = TRUE
    )
    
    # --- Save meaningful results to output files ---
    
    # Save the updated TreeSummarizedExperiment object
    saveRDS(tse, "tse_diversity_ordination.RDS")
    
    # Save alpha diversity and sample metadata as a CSV table
    alpha_df <- as.data.frame(colData(tse))
    write.csv(alpha_df, "alpha_diversity_metadata.csv", row.names = TRUE)
    
    # Save MDS ordination coordinates as a CSV table
    mds_coords <- as.data.frame(reducedDim(altExp(tse, "Genus"), "BrayCurtis"))
    write.csv(mds_coords, "mds_bray_curtis_coordinates.csv", row.names = TRUE)
    
    # Generate and save a PDF plot of the MDS ordination
    pdf("mds_ordination_plot.pdf", width = 8, height = 6)
    # Use scater's plotReducedDim to visualize the MDS, coloring by SampleType if available
    if ("SampleType" %in% colnames(colData(altExp(tse, "Genus")))) {
        p <- plotReducedDim(altExp(tse, "Genus"), dimred = "BrayCurtis", colour_by = "SampleType") +
            labs(title = "MDS Ordination (Bray-Curtis Distance at Genus Level)") +
            theme_minimal()
    } else {
        p <- plotReducedDim(altExp(tse, "Genus"), dimred = "BrayCurtis") +
            labs(title = "MDS Ordination (Bray-Curtis Distance at Genus Level)") +
            theme_minimal()
    }
    print(p)
    dev.off()

    writeLines(c(
        '"BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION":',
        paste0('    mia: ', as.character(packageVersion('mia')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_community_diversity_and_ordination.csv versions.yml
    """
}

workflow BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GlobalPatterns.RDS ] ]

    main:
    BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION(ch_input)

    emit:
    tables   = BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION.out.tables
    plots    = BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION.out.plots
    objects  = BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION.out.objects
    versions = BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION.out.versions
}
