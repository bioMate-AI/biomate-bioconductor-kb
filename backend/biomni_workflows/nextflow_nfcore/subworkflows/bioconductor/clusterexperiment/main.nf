#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clusterExperiment — rsec_automated_pipeline
// Run the complete automated RSEC pipeline to generate a robust consensus clustering, build a hierarchy, merge similar clusters, and find marker features.
// Input: fluidigmData, fluidigmColData
// Container: quay.io/biocontainers/bioconductor-clusterexperiment:2.30.0--r45ha27e39d_0
// R packages: SummarizedExperiment, clusterExperiment, igraph, phylobase, scran
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, clusterExperiment, limma
// Visualizations: heatmap, cluster plot
// QC: between-array normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Initialize SummarizedExperiment with count data
//  * 2. [Core Analysis] Filter out lowly expressed genes
//  * 3. [Core Analysis] Normalize counts and add as an assay
//  * 4. [Core Analysis] Run the unified RSEC wrapper
//  * 5. [Visualization & Output] Retrieve and visualize the primary cluster and cluster matrix
//  * 6. [Core Analysis] Perform differential expression to find cluster-specific marker features
//  * 7. [Visualization & Output] Visualize marker features using heatmaps

nextflow.enable.dsl = 2

process BIOC_CLUSTEREXPERIMENT_RSEC_AUTOMATED_PIPELINE {
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
    .bm_deps <- c("SummarizedExperiment", "clusterExperiment", "igraph", "phylobase", "scran")
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
        library(clusterExperiment)
        
        library(SummarizedExperiment)
        # Read user input files from the working directory
        if (file.exists("fluidigmData.rds")) {
          fluidigmData <- readRDS("fluidigmData.rds")
        } else if (file.exists("fluidigmData.RData")) {
          load("fluidigmData.RData")
        } else {
          stop("Error: fluidigmData file (RDS or RData) not found in the working directory.")
        }
        
        if (file.exists("fluidigmColData.rds")) {
          fluidigmColData <- readRDS("fluidigmColData.rds")
        } else if (file.exists("fluidigmColData.RData")) {
          load("fluidigmColData.RData")
        } else {
          stop("Error: fluidigmColData file (RDS or RData) not found in the working directory.")
        }
        
        # Initialize SummarizedExperiment with count data
        se<-SummarizedExperiment(fluidigmData,colData=fluidigmColData)
        
        # Filter out lowly expressed genes
        wh_zero <- which(rowSums(assay(se))==0)
        pass_filter <- apply(assay(se), 1, function(x) length(x[x >= 10]) >= 10)
        se <- se[pass_filter,]
        
        # Normalize counts and add as an assay
        fq <- round(limma::normalizeQuantiles(assay(se)))
        assays(se) <- c(SimpleList(normalized_counts=fq),assays(se))
        
        # Rename columns in colData
        wh<-which(colnames(colData(se)) %in% c("Cluster1","Cluster2"))
        colnames(colData(se))[wh]<-c("Published1","Published2")
        
        # Run the unified RSEC wrapper
        rsecFluidigm<-RSEC(se, isCount = TRUE, reduceMethod="PCA", nReducedDims=10, k0s = 4:15, alphas=c(0.1, 0.2, 0.3), ncores=1, random.seed=176201)
        
        # Retrieve primary cluster, table of clusters, and cluster matrix
        pc <- primaryCluster(rsecFluidigm)
        tc <- tableClusters(rsecFluidigm)
        cm <- clusterMatrix(rsecFluidigm)
        
        # Save retrieved cluster information to CSV files
        write.csv(data.frame(Sample = colnames(rsecFluidigm), Cluster = pc), "primary_clusters.csv", row.names = FALSE)
        write.csv(as.data.frame(tc), "table_clusters.csv", row.names = FALSE)
        write.csv(as.data.frame(cm), "cluster_matrix.csv", row.names = TRUE)
        
        # Save the RSEC object
        saveRDS(rsecFluidigm, "rsecFluidigm.rds")
        
        # Visualize the primary cluster and cluster matrix
        pdf("plot_clusters.pdf", width = 10, height = 8)
        plotClusters(rsecFluidigm,main="Clusters from RSEC", whichClusters="workflow", axisLine=-1)
        dev.off()
        
        # Perform differential expression to find cluster-specific marker features
        pairsAllRSEC<-getBestFeatures(rsecFluidigm,contrastType="Pairs",p.value=0.05, number=nrow(rsecFluidigm),DEMethod="edgeR")
        write.csv(pairsAllRSEC, "pairs_all_rsec.csv", row.names = FALSE)
        
        # Visualize marker features using heatmaps
        pdf("plot_heatmap.pdf", width = 10, height = 8)
        plotHeatmap(rsecFluidigm, whichClusters=c("makeConsensus","mergeClusters"),clusterSamplesData="dendrogramValue", clusterFeaturesData=unique(pairsAllRSEC[,"IndexInOriginal"]), main="Heatmap of features w/ significant pairwise differences", breaks=.99)
        dev.off()
        
        pdf("plot_contrast_heatmap.pdf", width = 10, height = 8)
        plotContrastHeatmap(rsecFluidigm, signif=pairsAllRSEC,nBlankLines=40,whichCluster="primary")
        dev.off()

    writeLines(c(
        '"BIOC_CLUSTEREXPERIMENT_RSEC_AUTOMATED_PIPELINE":',
        paste0('    clusterExperiment: ', as.character(packageVersion('clusterExperiment')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rsec_automated_pipeline.csv versions.yml
    """
}

workflow BIOC_CLUSTEREXPERIMENT_RSEC_AUTOMATED_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fluidigmData, fluidigmColData ] ]

    main:
    BIOC_CLUSTEREXPERIMENT_RSEC_AUTOMATED_PIPELINE(ch_input)

    emit:
    tables   = BIOC_CLUSTEREXPERIMENT_RSEC_AUTOMATED_PIPELINE.out.tables
    plots    = BIOC_CLUSTEREXPERIMENT_RSEC_AUTOMATED_PIPELINE.out.plots
    objects  = BIOC_CLUSTEREXPERIMENT_RSEC_AUTOMATED_PIPELINE.out.objects
    versions = BIOC_CLUSTEREXPERIMENT_RSEC_AUTOMATED_PIPELINE.out.versions
}
