#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clusterStab — cluster_number_and_stability_analysis
// Estimate the optimal number of clusters in microarray data and test the stability of the chosen clusters.
// Input: fibroEset
// Container: quay.io/biocontainers/bioconductor-clusterstab:1.82.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, clusterStab, genefilter
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter genes using coefficient of variation (CV) to avoid bias
//  * 2. [Core Analysis] Estimate the number of clusters using the benhur function
//  * 3. [Visualization & Output] Visualize the cluster number distribution using hist and ecdf
//  * 4. [Visualization & Output] Perform hierarchical clustering and plot the dendrogram
//  * 5. [Core Analysis] Test the stability of the selected number of clusters using clusterComp

nextflow.enable.dsl = 2

process BIOC_CLUSTERSTAB_CLUSTER_NUMBER_AND_STABILITY_ANALYSIS {
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
    library(clusterStab)
    library(genefilter)
    library(Biobase)
    
    # 1. Read the user input file from the working directory
    # The pipeline expects 'fibroEset' as an RDS file containing the ExpressionSet
    if (file.exists("fibroEset")) {
      fibroEset <- readRDS("fibroEset")
    } else if (file.exists("fibroEset.rds")) {
      fibroEset <- readRDS("fibroEset.rds")
    } else {
      stop("Error: Input file 'fibroEset' or 'fibroEset.rds' not found in the working directory.")
    }
    
    # Log2 transform the expression values
    exprs(fibroEset) <- log2(exprs(fibroEset))
    
    # Filter genes using coefficient of variation (CV) to avoid bias
    filt <- cv(0.1, Inf)
    index <- genefilter(fibroEset, filt)
    fb <- fibroEset[index,]
    
    # 2. Estimate the number of clusters using the benhur function
    bh <- benhur(fb, 0.7, 6, seednum = 12345)
    saveRDS(bh, "benhur_result.rds")
    
    # 3. Visualize the cluster number distribution using hist and ecdf
    pdf("benhur_histogram.pdf", width = 8, height = 6)
    hist(bh)
    dev.off()
    
    pdf("benhur_ecdf.pdf", width = 8, height = 6)
    ecdf(bh)
    dev.off()
    
    # 4. Perform hierarchical clustering and plot the dendrogram
    pdf("cluster_dendrogram.pdf", width = 10, height = 7)
    dend_labels <- if (ncol(pData(fibroEset)) >= 2) pData(fibroEset)[,2] else sampleNames(fibroEset)
    plot(hclust(dist(t(exprs(fibroEset[index,])))), labels = dend_labels, sub="", xlab="")
    dev.off()
    
    # 5. Test the stability of the selected number of clusters using clusterComp
    cmp <- clusterComp(fb, 2)
    saveRDS(cmp, "cluster_comp_result.rds")
    
    # Save the text summary of the cluster stability results
    sink("cluster_comp_summary.txt")
    print(cmp)
    sink()

    writeLines(c(
        '"BIOC_CLUSTERSTAB_CLUSTER_NUMBER_AND_STABILITY_ANALYSIS":',
        paste0('    clusterStab: ', as.character(packageVersion('clusterStab')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cluster_number_and_stability_analysis.csv versions.yml
    """
}

workflow BIOC_CLUSTERSTAB_CLUSTER_NUMBER_AND_STABILITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fibroEset ] ]

    main:
    BIOC_CLUSTERSTAB_CLUSTER_NUMBER_AND_STABILITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CLUSTERSTAB_CLUSTER_NUMBER_AND_STABILITY_ANALYSIS.out.tables
    plots    = BIOC_CLUSTERSTAB_CLUSTER_NUMBER_AND_STABILITY_ANALYSIS.out.plots
    objects  = BIOC_CLUSTERSTAB_CLUSTER_NUMBER_AND_STABILITY_ANALYSIS.out.objects
    versions = BIOC_CLUSTERSTAB_CLUSTER_NUMBER_AND_STABILITY_ANALYSIS.out.versions
}
