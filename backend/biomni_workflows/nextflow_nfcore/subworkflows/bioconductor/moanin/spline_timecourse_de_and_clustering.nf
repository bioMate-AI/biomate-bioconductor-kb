#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: moanin — spline_timecourse_de_and_clustering
// Fit smooth splines to model gene expression trajectories over time, perform spline-based differential expression, estimate log-fold changes, visualize trajector
// Input: preData, preMeta
// Container: quay.io/biocontainers/bioconductor-moanin:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: moanin
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a Moanin model object using create_moanin_model
//  * 2. [Core Analysis] Perform spline-based differential expression using DE_timecourse
//  * 3. [Core Analysis] Estimate log-fold changes across the time-course using estimate_log_fold_change
//  * 4. [Visualization & Output] Visualize top genes using plot_splines_data
//  * 5. [Core Analysis] Cluster trajectories using splines_kmeans
//  * 6. [Core Analysis] Score and assign additional genes to clusters using splines_kmeans_score_and_label

nextflow.enable.dsl = 2

process BIOC_MOANIN_SPLINE_TIMECOURSE_DE_AND_CLUSTERING {
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
    .bm_deps <- c("moanin")
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
    library(moanin)
    
    # 1. Read User Input Files
    # Expecting preData (matrix of raw counts) and preMeta (metadata data frame)
    # We will look for .rds, .csv, or .tsv files in the working directory.
    
    if (file.exists("preData.rds")) {
      preData <- readRDS("preData.rds")
    } else if (file.exists("preData.csv")) {
      preData <- as.matrix(read.csv("preData.csv", row.names=1, check.names=FALSE))
    } else if (file.exists("preData.tsv")) {
      preData <- as.matrix(read.delim("preData.tsv", row.names=1, check.names=FALSE))
    } else {
      stop("Error: preData file (preData.rds, preData.csv, or preData.tsv) not found in the working directory.")
    }
    
    if (file.exists("preMeta.rds")) {
      preMeta <- readRDS("preMeta.rds")
    } else if (file.exists("preMeta.csv")) {
      preMeta <- read.csv("preMeta.csv", row.names=1, check.names=FALSE)
    } else if (file.exists("preMeta.tsv")) {
      preMeta <- read.delim("preMeta.tsv", row.names=1, check.names=FALSE)
    } else {
      stop("Error: preMeta file (preMeta.rds, preMeta.csv, or preMeta.tsv) not found in the working directory.")
    }
    
    # Ensure preData is a matrix
    preData <- as.matrix(preData)
    
    # Extract group and time variables dynamically (assuming first two columns)
    group_var <- colnames(preMeta)[1]
    time_var <- colnames(preMeta)[2]
    
    # 2. Create Moanin Model Object
    moaninObject <- create_moanin_model(data=preData, meta=preMeta, 
                                group_variable=group_var, time_variable=time_var, log_transform=TRUE)
    
    # 3. Perform spline-based differential expression
    groups <- unique(as.character(preMeta[[group_var]]))
    if (length(groups) < 2) {
      stop("Error: At least two groups are required for differential expression.")
    }
    group_combs <- combn(groups, 2)
    timecourseContrasts <- paste(group_combs[1, ], group_combs[2, ], sep="-")
    
    splinePre <- DE_timecourse(moaninObject, contrasts=timecourseContrasts,
         use_voom_weights=TRUE)
    
    # Save DE results
    write.csv(as.data.frame(splinePre), "spline_de_results.csv", row.names=TRUE)
    
    # 4. Estimate log-fold changes
    log_fold_change_timepoints <- estimate_log_fold_change(
        moaninObject, contrasts=timecourseContrasts, method="sum")
    
    # Save log-fold changes
    write.csv(as.data.frame(log_fold_change_timepoints), "log_fold_change_timepoints.csv", row.names=TRUE)
    
    # 5. Visualize top genes
    first_contrast <- timecourseContrasts[1]
    qval_col <- paste0(first_contrast, "_qval")
    pval_col <- paste0(first_contrast, "_pval")
    
    whSig <- which(splinePre[, qval_col] < 0.05)
    
    # Fallback to top 50 by p-value if none are significant at 0.05 to ensure plotting works
    if (length(whSig) == 0) {
      whSig <- order(splinePre[, pval_col])[1:min(50, nrow(splinePre))]
    }
    
    deGenes <- order(abs(
        log_fold_change_timepoints)[whSig, first_contrast],
        decreasing=TRUE)[1:min(10, length(whSig))]
    
    pdf("top_de_genes_splines.pdf", width=10, height=8)
    plot_splines_data(moaninObject[whSig, ][deGenes,],
        smooth=TRUE, mar=c(1.5,2.5,2,0.1))
    dev.off()
    
    # 6. Cluster trajectories using splines_kmeans
    kmeans_clusters <- splines_kmeans(moaninObject, n_clusters=3,
        random_seed=42, 
        n_init=20)
    
    # Save clustering object
    saveRDS(kmeans_clusters, "kmeans_clusters.rds")
    
    # Visualize centroids
    pdf("kmeans_centroids_splines.pdf", width=10, height=8)
    plot_splines_data(
        data=kmeans_clusters\$centroids, moaninObject,
        smooth=TRUE)
    dev.off()
    
    # 7. Score and assign additional genes to clusters
    scores_and_labels <- splines_kmeans_score_and_label(
        object=moaninObject, data=preData, kmeans_clusters=kmeans_clusters)
    
    # Save scores and labels
    write.csv(as.data.frame(scores_and_labels\$scores), "scores_and_labels_scores.csv", row.names=TRUE)
    write.csv(data.frame(Gene=names(scores_and_labels\$labels), Cluster=scores_and_labels\$labels), "scores_and_labels_labels.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_MOANIN_SPLINE_TIMECOURSE_DE_AND_CLUSTERING":',
        paste0('    moanin: ', as.character(packageVersion('moanin')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spline_timecourse_de_and_clustering.csv versions.yml
    """
}

workflow BIOC_MOANIN_SPLINE_TIMECOURSE_DE_AND_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ preData, preMeta ] ]

    main:
    BIOC_MOANIN_SPLINE_TIMECOURSE_DE_AND_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_MOANIN_SPLINE_TIMECOURSE_DE_AND_CLUSTERING.out.tables
    plots    = BIOC_MOANIN_SPLINE_TIMECOURSE_DE_AND_CLUSTERING.out.plots
    objects  = BIOC_MOANIN_SPLINE_TIMECOURSE_DE_AND_CLUSTERING.out.objects
    versions = BIOC_MOANIN_SPLINE_TIMECOURSE_DE_AND_CLUSTERING.out.versions
}
