#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowMatch — pairwise_cluster_matching
// Match cell populations (clusters) across a pair of flow cytometry samples using the Mixed Edge Cover (MEC) algorithm.
// Input: sample1.csv, sample2.csv
// Container: quay.io/biocontainers/bioconductor-flowmatch:1.46.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowMatch
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Cluster both samples using a clustering algorithm (e.g., kmeans). 2. Create ClusteredSample S4 objects for both samples to encapsu

nextflow.enable.dsl = 2

process BIOC_FLOWMATCH_PAIRWISE_CLUSTER_MATCHING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    library(flowMatch)
    
    # Set seed for reproducible clustering
    set.seed(1234)
    
    # Read user input files
    sample1 <- as.matrix(read.csv("sample1.csv"))
    sample2 <- as.matrix(read.csv("sample2.csv"))
    
    # 1. Cluster both samples using a clustering algorithm (kmeans)
    clust1 = kmeans(sample1, centers=4, nstart=20)
    clust2 = kmeans(sample2, centers=4, nstart=20)
    cluster.labels1 = clust1\$cluster
    cluster.labels2 = clust2\$cluster
    
    # 2. Create ClusteredSample S4 objects for both samples
    clustSample1 = ClusteredSample(labels=cluster.labels1, sample=sample1)
    clustSample2 = ClusteredSample(labels=cluster.labels2, sample=sample2)
    
    # 3. Match clusters across the sample pair using match.clusters
    mec = match.clusters(clustSample1, clustSample2, dist.type="Mahalanobis", unmatch.penalty=99999)
    
    # 4. Retrieve and summarize the matching results
    class_info <- class(mec)
    print(class_info)
    
    # Capture summary output
    sink("matching_summary.txt")
    cat("Class of matching object:\n")
    print(class_info)
    cat("\nSummary of matching:\n")
    summary(mec)
    sink()
    
    # Write meaningful output files
    # Save the S4 ClusterMatch object
    saveRDS(mec, file = "mec_result.rds")
    
    # Save cluster assignments for both samples
    write.csv(data.frame(Cell = seq_along(cluster.labels1), Cluster = cluster.labels1), 
              "sample1_clusters.csv", row.names = FALSE)
    write.csv(data.frame(Cell = seq_along(cluster.labels2), Cluster = cluster.labels2), 
              "sample2_clusters.csv", row.names = FALSE)
    
    # Generate diagnostic plots of the clustered samples
    pdf("clustered_samples.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    tryCatch({
      plot(sample1, clustSample1)
      title(main = "Sample 1 Clusters")
    }, error = function(e) {
      message("Could not plot Sample 1: ", e\$message)
    })
    
    tryCatch({
      plot(sample2, clustSample2)
      title(main = "Sample 2 Clusters")
    }, error = function(e) {
      message("Could not plot Sample 2: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_FLOWMATCH_PAIRWISE_CLUSTER_MATCHING":',
        paste0('    flowMatch: ', as.character(packageVersion('flowMatch')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_cluster_matching.csv versions.yml
    """
}

workflow BIOC_FLOWMATCH_PAIRWISE_CLUSTER_MATCHING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample1.csv, sample2.csv ] ]

    main:
    BIOC_FLOWMATCH_PAIRWISE_CLUSTER_MATCHING(ch_input)

    emit:
    tables   = BIOC_FLOWMATCH_PAIRWISE_CLUSTER_MATCHING.out.tables
    plots    = BIOC_FLOWMATCH_PAIRWISE_CLUSTER_MATCHING.out.plots
    objects  = BIOC_FLOWMATCH_PAIRWISE_CLUSTER_MATCHING.out.objects
    versions = BIOC_FLOWMATCH_PAIRWISE_CLUSTER_MATCHING.out.versions
}
