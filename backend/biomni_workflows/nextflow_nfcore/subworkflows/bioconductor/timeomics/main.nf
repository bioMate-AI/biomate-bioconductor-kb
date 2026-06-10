#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: timeOmics — single_omic_longitudinal_clustering
// Model and cluster longitudinal features from a single omics dataset to find groups of features with similar temporal profiles.
// Input: sim.data, time
// Container: quay.io/biocontainers/bioconductor-timeomics:1.22.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: lmms, mixOmics, timeOmics
// Visualizations: PCA plot, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter low-variation features using a coefficient of variation threshold
//  * 2. [Core Analysis] Model features as a function of time using linear mixed model splines
//  * 3. [Core Analysis] Filter out noisy or straight-line profiles
//  * 4. [Core Analysis] Perform PCA and optimize the number of components
//  * 5. [Visualization & Output] Extract clusters and plot longitudinal profiles
//  * 6. [Core Analysis] Optimize feature selection using sparse PCA to identify a cluster signature

nextflow.enable.dsl = 2

process BIOC_TIMEOMICS_SINGLE_OMIC_LONGITUDINAL_CLUSTERING {
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
    library(timeOmics)
    library(mixOmics)
    library(lmms)
    
    # Read user input files from the working directory
    if (file.exists("sim.data.rds")) {
      sim.data <- readRDS("sim.data.rds")
    } else if (file.exists("sim.data.csv")) {
      sim.data <- as.matrix(read.csv("sim.data.csv", row.names = 1))
    } else {
      stop("Error: 'sim.data' (RDS or CSV) not found in the working directory.")
    }
    
    if (file.exists("time.rds")) {
      time <- readRDS("time.rds")
    } else if (file.exists("time.csv")) {
      time <- as.numeric(unlist(read.csv("time.csv", header = FALSE)))
    } else {
      stop("Error: 'time' (RDS or CSV) not found in the working directory.")
    }
    
    # Stage 1: Filtering
    remove.low.cv <- function(X, cutoff = 0.5){
      # var.coef
      cv <- unlist(lapply(as.data.frame(X), function(x) abs(sd(x)/mean(x))))
      return(X[,cv > cutoff])
    }
    data.filtered <- remove.low.cv(sim.data, 0.5)
    
    # Stage 2: LMMS modeling
    lmms.output <- lmms::lmmSpline(data = data.filtered, time = time,
                                   sampleID = rownames(data.filtered), deri = FALSE,
                                   basis = "p-spline", numCores = 1, timePredict = sort(unique(time)),
                                   keepModels = TRUE)
    
    # Stage 3: Profile filtering
    filter.res <- lmms.filter.lines(data = data.filtered, lmms.obj = lmms.output, time = time)
    profile.filtered <- filter.res\$filtered
    
    # Stage 4: PCA
    pca.res <- pca(X = profile.filtered, ncomp = 5, scale = FALSE, center = FALSE)
    pca.ncomp <- getNcomp(pca.res, max.ncomp = 5, X = profile.filtered, scale = FALSE, center = FALSE)
    
    # Use the optimized ncomp from getNcomp
    opt.ncomp <- pca.ncomp\$choice.ncomp
    
    pca.res <- pca(X = profile.filtered, ncomp = opt.ncomp, scale = FALSE, center = FALSE)
    pca.cluster <- getCluster(pca.res)
    
    # Save PCA longitudinal clustering plot
    pdf("pca_longitudinal_clustering.pdf")
    plotLong(pca.res, scale = FALSE, center = FALSE, title = "PCA longitudinal clustering")
    dev.off()
    
    # Stage 5 & 6: sparse PCA
    # Dynamically set test.keepX based on the number of features available
    max_k <- min(10, ncol(profile.filtered))
    test.keepX.vals <- if (max_k >= 2) 2:max_k else max_k
    
    tune.spca.res <- tuneCluster.spca(X = profile.filtered, ncomp = opt.ncomp, test.keepX = test.keepX.vals)
    spca.res <- spca(X = profile.filtered, ncomp = opt.ncomp, keepX = tune.spca.res\$choice.keepX, scale = FALSE)
    spca.cluster <- getCluster(spca.res)
    
    # Save sPCA longitudinal clustering plot
    pdf("spca_longitudinal_clustering.pdf")
    plotLong(spca.res, title = "sPCA clustering")
    dev.off()
    
    # Save additional outputs
    write.csv(pca.cluster, "pca_clusters.csv", row.names = FALSE)
    write.csv(spca.cluster, "spca_clusters.csv", row.names = FALSE)
    
    saveRDS(pca.res, "pca_res.rds")
    saveRDS(pca.ncomp, "pca_ncomp.rds")
    saveRDS(tune.spca.res, "tune_spca.rds")
    saveRDS(spca.res, "spca_res.rds")
    
    # Save PCA ncomp plot
    pdf("pca_ncomp_plot.pdf")
    plot(pca.ncomp)
    dev.off()

    writeLines(c(
        '"BIOC_TIMEOMICS_SINGLE_OMIC_LONGITUDINAL_CLUSTERING":',
        paste0('    timeOmics: ', as.character(packageVersion('timeOmics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_omic_longitudinal_clustering.csv versions.yml
    """
}

workflow BIOC_TIMEOMICS_SINGLE_OMIC_LONGITUDINAL_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sim.data, time ] ]

    main:
    BIOC_TIMEOMICS_SINGLE_OMIC_LONGITUDINAL_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_TIMEOMICS_SINGLE_OMIC_LONGITUDINAL_CLUSTERING.out.tables
    plots    = BIOC_TIMEOMICS_SINGLE_OMIC_LONGITUDINAL_CLUSTERING.out.plots
    objects  = BIOC_TIMEOMICS_SINGLE_OMIC_LONGITUDINAL_CLUSTERING.out.objects
    versions = BIOC_TIMEOMICS_SINGLE_OMIC_LONGITUDINAL_CLUSTERING.out.versions
}
