#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowCyBar — nmds_analysis
// Visualize sample dissimilarity using Nonmetric Multidimensional Scaling (NMDS) and project environmental or gate variables.
// Input: Cell_number_sample.txt, Abiotic_data_sample.txt
// Container: quay.io/biocontainers/bioconductor-flowcybar:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCyBar
// Visualizations: ordination plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read and normalize cell abundance data
//  * 2. [Input & Preparation] Define sample group assignments
//  * 3. [Input & Preparation] Read abiotic/environmental parameter data
//  * 4. [Visualization & Output] Perform NMDS and plot samples, optionally overlaying groups and significant abiotic/gate vectors

nextflow.enable.dsl = 2

process BIOC_FLOWCYBAR_NMDS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    .bm_deps <- c("flowCyBar")
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
        
        # Load required library
        library(flowCyBar)
        
        # Read user input files from the working directory
        Cell_number_sample <- read.table("Cell_number_sample.txt", header=TRUE, sep="\t")
        Abiotic_data_sample <- read.table("Abiotic_data_sample.txt", header=TRUE, sep="\t")
        
        # Open PDF device to save the NMDS plots
        pdf("nmds_analysis_plots.pdf", width=10, height=8)
        
        # Normalize cell abundance data
        Normalized_mean <- normalize(Cell_number_sample[,-1], digits=2)
        Normalized_mean <- data.frame(data.matrix(Normalized_mean))
        
        # Save normalized values to a file
        write.table(Normalized_mean, file="normalized_mean.txt", row.names=TRUE, quote=FALSE, sep="\t")
        
        # Perform NMDS and plot samples under various configurations
        nmds(Cell_number_sample[,-1])
        
        nmds(Normalized_mean)
        
        nmds(Normalized_mean, main="NMDS plot of \nnormalized cell numbers", type="b", pos=3, pch=2, col="red")
        
        # Define sample group assignments dynamically based on the number of samples
        groups <- data.frame("groups"=as.numeric(gl(3, ceiling(nrow(Normalized_mean)/3), length=nrow(Normalized_mean))))
        
        nmds(Normalized_mean, group=groups, main="NMDS plot of \nnormalized cell numbers")
        
        nmds(Normalized_mean, group=groups, main="NMDS plot of \nnormalized cell numbers", abiotic=Abiotic_data_sample[,-1], verbose=TRUE)
        
        # Safely determine column indices for subsets to avoid out-of-bounds errors
        n_cols <- ncol(Abiotic_data_sample)
        mid_col <- max(2, floor(n_cols / 2) + 1)
        
        nmds(Normalized_mean, group=groups, main="NMDS plot of \nnormalized cell numbers", abiotic=Abiotic_data_sample[, mid_col:n_cols, drop=FALSE], verbose=TRUE)
        
        nmds(Normalized_mean, group=groups, main="NMDS plot of \nnormalized cell numbers", abiotic=Abiotic_data_sample[, 2:max(2, mid_col - 1), drop=FALSE], verbose=TRUE)
        
        nmds(Normalized_mean, group=groups, main="NMDS plot of \nnormalized cell numbers", legend_pos="topright", abiotic=Abiotic_data_sample[,-1], p.max=0.01, col_abiotic="darkred", verbose=TRUE)
        
        # Change row names to sample names and plot again
        rownames(Normalized_mean) <- Abiotic_data_sample[,1]
        
        final_nmds <- nmds(Normalized_mean, group=groups, main="NMDS plot of \nnormalized cell numbers", legend_pos="topright", abiotic=Abiotic_data_sample[,-1], p.max=0.01, col_abiotic="darkred", verbose=TRUE)
        
        # Close the PDF device
        dev.off()
        
        # Save the final NMDS result object
        saveRDS(final_nmds, file="nmds_final_result.rds")

    writeLines(c(
        '"BIOC_FLOWCYBAR_NMDS_ANALYSIS":',
        paste0('    flowCyBar: ', as.character(packageVersion('flowCyBar')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nmds_analysis.csv versions.yml
    """
}

workflow BIOC_FLOWCYBAR_NMDS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Cell_number_sample.txt, Abiotic_data_sample.txt ] ]

    main:
    BIOC_FLOWCYBAR_NMDS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FLOWCYBAR_NMDS_ANALYSIS.out.tables
    plots    = BIOC_FLOWCYBAR_NMDS_ANALYSIS.out.plots
    objects  = BIOC_FLOWCYBAR_NMDS_ANALYSIS.out.objects
    versions = BIOC_FLOWCYBAR_NMDS_ANALYSIS.out.versions
}
