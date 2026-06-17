#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Oscope — oscillating_gene_pipeline
// Identify co-regulated oscillating gene clusters and reconstruct the cyclic order of unsynchronized single-cell RNA-seq samples.
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-oscope:1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Oscope
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Library size normalization using MedianNorm and GetNormalizedMat
//  * 2. [Core Analysis] Mean and variance estimation and gene filtering using CalcMV
//  * 3. [Core Analysis] Rescaling expression measurements to [-1, 1] using NormForSine
//  * 4. [Core Analysis] Paired-sine modeling using OscopeSine
//  * 5. [Core Analysis] K-medoids clustering using OscopeKM
//  * 6. [Core Analysis] Flagging and removing invalid clusters using FlagCluster
//  * 7. [Core Analysis] Reconstructing base cycle cell orders using OscopeENI

nextflow.enable.dsl = 2

process BIOC_OSCOPE_OSCILLATING_GENE_PIPELINE {
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
    .bm_deps <- c("Oscope")
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
        library(Oscope)
        
        # Set seed for reproducibility
        set.seed(10)
        
        # 1. Read User Input
        # The pipeline reads expression_matrix.csv from the working directory.
        # This is a G-by-S matrix of raw gene expression values.
        if (!file.exists("expression_matrix.csv")) {
          stop("Error: 'expression_matrix.csv' not found in the working directory.")
        }
        
        OscopeExampleData <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
        
        # Open PDF device to capture all generated plots (Mean-Variance plot and recovered profiles)
        pdf("oscope_pipeline_plots.pdf", width = 8, height = 10)
        
        # 2. Library size normalization
        Sizes <- MedianNorm(OscopeExampleData)
        DataNorm <- GetNormalizedMat(OscopeExampleData, Sizes)
        
        # 3. Mean and variance estimation and gene filtering
        # This call automatically plots the Mean-Variance relationship to the active PDF device
        MV <- CalcMV(Data = OscopeExampleData, Sizes = Sizes)
        DataSubset <- DataNorm[MV\$GeneToUse,]
        
        # 4. Rescaling expression measurements to [-1, 1]
        DataInput <- NormForSine(DataSubset)
        
        # 5. Paired-sine modeling
        SineRes <- OscopeSine(DataInput, parallel=TRUE)
        
        # 6. K-medoids clustering
        KMRes <- OscopeKM(SineRes, maxK = 10)
        
        # 7. Flagging and removing invalid clusters
        ToRM <- FlagCluster(SineRes, KMRes, DataInput)
        
        # Handle flagging safely while preserving the exact documented code structure
        if (length(ToRM\$FlagID) > 0) {
          KMResUse <- KMRes[-ToRM\$FlagID]
        } else {
          KMResUse <- KMRes
        }
        
        # 8. Reconstructing base cycle cell orders using Extended Nearest Insertion
        ENIRes <- OscopeENI(KMRes = KMResUse, Data = DataInput, NCThre = 100, parallel=TRUE)
        
        # Reorder the normalized expression matrix based on the recovered order of cluster 2
        if ("cluster2" %in% names(ENIRes)) {
          DataNorm2 <- DataNorm[, ENIRes[["cluster2"]]]
          write.csv(DataNorm2, "reordered_cluster2_expression.csv", row.names = TRUE)
        }
        
        # 9. Visualization of recovered profiles
        # Visualize cluster 2 profiles if available
        if ("cluster2" %in% names(ENIRes) && "cluster2" %in% names(KMResUse)) {
          genes_to_plot <- KMResUse[["cluster2"]]
          n_plots <- min(6, length(genes_to_plot))
          if (n_plots > 0) {
            par(mfrow = c(3, 2))
            for (i in 1:n_plots) {
              plot(DataNorm[genes_to_plot[i], ENIRes[["cluster2"]]],
                   xlab = "Recovered order", ylab = "Expression",
                   main = genes_to_plot[i])
            }
          }
        }
        
        # Visualize cluster 3 profiles if available
        if ("cluster3" %in% names(ENIRes) && "cluster3" %in% names(KMResUse)) {
          genes_to_plot <- KMResUse[["cluster3"]]
          n_plots <- min(6, length(genes_to_plot))
          if (n_plots > 0) {
            par(mfrow = c(3, 2))
            for (i in 1:n_plots) {
              plot(DataNorm[genes_to_plot[i], ENIRes[["cluster3"]]],
                   xlab = "Recovered order", ylab = "Expression",
                   main = genes_to_plot[i])
            }
          }
        }
        
        # Close the PDF device
        dev.off()
        
        # 10. Save meaningful results to files
        write.csv(DataNorm, "normalized_expression.csv", row.names = TRUE)
        write.csv(DataSubset, "high_mv_expression_subset.csv", row.names = TRUE)
        saveRDS(KMResUse, "oscope_clusters_retained.rds")
        saveRDS(ENIRes, "oscope_eni_results.rds")
        
        message("Oscope pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_OSCOPE_OSCILLATING_GENE_PIPELINE":',
        paste0('    Oscope: ', as.character(packageVersion('Oscope')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_oscillating_gene_pipeline.csv versions.yml
    """
}

workflow BIOC_OSCOPE_OSCILLATING_GENE_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_OSCOPE_OSCILLATING_GENE_PIPELINE(ch_input)

    emit:
    tables   = BIOC_OSCOPE_OSCILLATING_GENE_PIPELINE.out.tables
    plots    = BIOC_OSCOPE_OSCILLATING_GENE_PIPELINE.out.plots
    objects  = BIOC_OSCOPE_OSCILLATING_GENE_PIPELINE.out.objects
    versions = BIOC_OSCOPE_OSCILLATING_GENE_PIPELINE.out.versions
}
