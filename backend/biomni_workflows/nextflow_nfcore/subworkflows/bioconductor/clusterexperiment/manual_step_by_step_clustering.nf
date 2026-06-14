#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clusterExperiment — manual_step_by_step_clustering
// Manually execute and fine-tune each step of the clustering workflow (clusterMany, makeConsensus, makeDendrogram, mergeClusters) to have granular control over pa
// Input: se
// Container: quay.io/biocontainers/bioconductor-clusterexperiment:2.30.0--r45ha27e39d_0
// R packages: SummarizedExperiment, clusterExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, clusterExperiment
// Visualizations: dendrogram, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run multiple clusterings across parameter combinations using clusterMany
//  * 2. [Core Analysis] Generate a consensus clustering using makeConsensus with custom proportions
//  * 3. [Input & Preparation] Build a cluster hierarchy using makeDendrogram
//  * 4. [Core Analysis] Merge similar clusters based on DE testing using mergeClusters
//  * 5. [Core Analysis] Assign unassigned samples to the nearest cluster using assignUnassigned
//  * 6. [Visualization & Output] Visualize the workflow progression using plotClustersWorkflow and plotCoClustering

nextflow.enable.dsl = 2

process BIOC_CLUSTEREXPERIMENT_MANUAL_STEP_BY_STEP_CLUSTERING {
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
    .bm_deps <- c("SummarizedExperiment", "clusterExperiment")
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
    # Read the user input file 'se' from the working directory
    # Assuming 'se' is a serialized SummarizedExperiment object (RDS format)
    if (!file.exists("se")) {
      stop("Input file 'se' not found in the working directory.")
    }
    se <- readRDS("se")
    
    # Ensure required colData columns exist so the exact documented plotClusters call does not fail
    if (!"Biological_Condition" %in% colnames(colData(se))) {
      colData(se)\$Biological_Condition <- rep("Unknown", ncol(se))
    }
    if (!"Published2" %in% colnames(colData(se))) {
      colData(se)\$Published2 <- rep("Unknown", ncol(se))
    }
    
    # 1. Run multiple clusterings across parameter combinations using clusterMany
    ce <- clusterMany(
      se, 
      clusterFunction = "pam", 
      ks = 5:10, 
      minSizes = 5, 
      isCount = TRUE, 
      reduceMethod = c("PCA", "var"), 
      nFilterDims = c(100, 500, 1000), 
      nReducedDims = c(5, 15, 50), 
      run = TRUE
    )
    
    # Save plot from clusterMany
    pdf("clusters_from_clusterMany.pdf", width = 10, height = 8)
    plotClusters(
      ce, 
      main = "Clusters from clusterMany", 
      whichClusters = "workflow", 
      colData = c("Biological_Condition", "Published2"), 
      axisLine = -1
    )
    dev.off()
    
    # 2. Generate a consensus clustering using makeConsensus with custom proportions
    ce <- makeConsensus(ce, proportion = 1)
    
    wh <- which(clusterLabels(ce) == "makeConsensus")
    if (length(wh) != 1) {
      stop("Expected exactly one 'makeConsensus' cluster label to rename.")
    } else {
      clusterLabels(ce)[wh] <- "makeConsensus,1"
    }
    
    ce <- makeConsensus(ce, proportion = 0.7, clusterLabel = "makeConsensus,0.7")
    ce <- makeConsensus(ce, proportion = 0.7, minSize = 3, clusterLabel = "makeConsensus,final")
    
    # Save co-clustering plot
    pdf("co_clustering.pdf", width = 8, height = 8)
    plotCoClustering(ce)
    dev.off()
    
    # 3. Build a cluster hierarchy using makeDendrogram
    ce <- makeDendrogram(ce, reduceMethod = "var", nDims = 500)
    
    # Save dendrogram plot
    pdf("dendrogram.pdf", width = 8, height = 8)
    plotDendrogram(ce)
    dev.off()
    
    # 4. Merge similar clusters based on DE testing using mergeClusters
    # Preview/plot the merge info
    pdf("merge_clusters_preview.pdf", width = 8, height = 8)
    mergeClusters(ce, mergeMethod = "adjP", DEMethod = "edgeR", plotInfo = "mergeMethod")
    dev.off()
    
    # Perform the actual merge
    ce <- mergeClusters(ce, mergeMethod = "adjP", DEMethod = "edgeR", cutoff = 0.05)
    
    # 5. Assign unassigned samples to the nearest cluster using assignUnassigned
    ce <- assignUnassigned(
      ce, 
      whichCluster = "mergeClusters", 
      reduceMethod = "PCA", 
      nDim = 50, 
      makePrimary = FALSE, 
      filterIgnoresUnassigned = TRUE, 
      clusterLabel = "mergeClusters_AssignToCluster"
    )
    
    # 6. Visualize the workflow progression using plotClustersWorkflow
    pdf("workflow_progression.pdf", width = 10, height = 8)
    plotClustersWorkflow(ce, whichClusters = "workflow")
    dev.off()
    
    # Save meaningful outputs to files
    saveRDS(ce, "ce_final.rds")
    
    # Export cluster assignments as a CSV table
    cluster_matrix <- clusterMatrix(ce)
    write.csv(cluster_matrix, "cluster_assignments.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_CLUSTEREXPERIMENT_MANUAL_STEP_BY_STEP_CLUSTERING":',
        paste0('    clusterExperiment: ', as.character(packageVersion('clusterExperiment')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_manual_step_by_step_clustering.csv versions.yml
    """
}

workflow BIOC_CLUSTEREXPERIMENT_MANUAL_STEP_BY_STEP_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ se ] ]

    main:
    BIOC_CLUSTEREXPERIMENT_MANUAL_STEP_BY_STEP_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_CLUSTEREXPERIMENT_MANUAL_STEP_BY_STEP_CLUSTERING.out.tables
    plots    = BIOC_CLUSTEREXPERIMENT_MANUAL_STEP_BY_STEP_CLUSTERING.out.plots
    objects  = BIOC_CLUSTEREXPERIMENT_MANUAL_STEP_BY_STEP_CLUSTERING.out.objects
    versions = BIOC_CLUSTEREXPERIMENT_MANUAL_STEP_BY_STEP_CLUSTERING.out.versions
}
