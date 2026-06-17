#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: survClust — integrative_multi_omic_clustering
// Perform supervised integrative clustering on multiple genomic data types (e.g., mutation and copy number) weighted by survival outcome.
// Input: uvm_dat, uvm_survdat
// Container: quay.io/biocontainers/bioconductor-survclust:1.4.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, survClust, survival
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Execute Cross-Validation
//  * 3. [Visualization & Output] Summarize and Plot Performance Metrics
//  * 4. [Visualization & Output] Consolidate Cluster Assignments (k=4)
//  * 5. [Visualization & Output] Survival Analysis (Kaplan-Meier Plot)

nextflow.enable.dsl = 2

process BIOC_SURVCLUST_INTEGRATIVE_MULTI_OMIC_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("survClust", "survival", "BiocParallel")
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
    library(survClust)
    library(survival)
    library(BiocParallel)
    
    # Set up parallel backend safely
    if (.Platform\$OS.type == "windows") {
      register(SerialParam())
    } else {
      register(MulticoreParam(workers = min(2, parallel::detectCores())))
    }
    
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    
    # Load uvm_dat (list of matrices/data frames)
    if (file.exists("uvm_dat.rds")) {
      uvm_dat <- readRDS("uvm_dat.rds")
    } else if (file.exists("uvm_dat.RData")) {
      env <- new.env()
      load("uvm_dat.RData", envir = env)
      uvm_dat <- env[[names(env)[1]]]
    } else {
      stop("Error: Required input file 'uvm_dat.rds' or 'uvm_dat.RData' not found in the working directory.")
    }
    
    # Load uvm_survdat (matrix or data frame with survival time and event status)
    if (file.exists("uvm_survdat.rds")) {
      uvm_survdat <- readRDS("uvm_survdat.rds")
    } else if (file.exists("uvm_survdat.csv")) {
      uvm_survdat <- read.csv("uvm_survdat.csv", row.names = 1)
    } else if (file.exists("uvm_survdat.RData")) {
      env <- new.env()
      load("uvm_survdat.RData", envir = env)
      uvm_survdat <- env[[names(env)[1]]]
    } else {
      stop("Error: Required input file 'uvm_survdat.rds', 'uvm_survdat.csv', or 'uvm_survdat.RData' not found in the working directory.")
    }
    
    # Ensure uvm_survdat is a matrix or data frame with appropriate format
    uvm_survdat <- as.matrix(uvm_survdat)
    
    # ==========================================
    # --- Execute Cross-Validation ---
    # ==========================================
    
    cv_rounds = 10
    
    # Function to do cross validation 
    uvm_all_cvrounds<-function(kk){
        this.fold<-3
        fit<-list()
        for (i in seq_len(cv_rounds)){
            fit[[i]] <- cv_survclust(uvm_dat,uvm_survdat,kk,this.fold)
            print(paste0("finished ", i, " rounds for k= ", kk))
        }
        return(fit)
    }
    
    # Run cross-validation across k = 2 to 7
    cv.fit<-bplapply(2:7, uvm_all_cvrounds)
    
    # Assign to the variable name used in the vignette's downstream analysis
    uvm_survClust_cv.fit <- cv.fit
    
    # Save the raw cross-validation fit object
    saveRDS(uvm_survClust_cv.fit, "uvm_survClust_cv_fit.rds")
    
    # ==========================================
    # --- Summarize and Plot Performance Metrics ---
    # ==========================================
    
    ss_stats <- getStats(uvm_survClust_cv.fit, kk=7, cvr=10)
    saveRDS(ss_stats, "ss_stats.rds")
    
    # Plot and save the stats
    pdf("survClust_stats_plot.pdf", width = 8, height = 8)
    plotStats(ss_stats, 2:7)
    dev.off()
    
    # ==========================================
    # --- Consolidate Cluster Assignments (k=4) ---
    # ==========================================
    
    k4 <- cv_voting(uvm_survClust_cv.fit, getDist(uvm_dat, uvm_survdat), pick_k=4)
    
    # Save cluster assignments
    write.csv(data.frame(Sample = names(k4), Cluster = k4), "cluster_assignments_k4.csv", row.names = FALSE)
    
    # Print table of cluster sizes
    print("Cluster assignment table for k=4:")
    print(table(k4))
    
    # ==========================================
    # --- Survival Analysis (Kaplan-Meier Plot) ---
    # ==========================================
    
    pdf("survClust_km_plot.pdf", width = 7, height = 7)
    plot(survfit(Surv(uvm_survdat[,1], uvm_survdat[,2])~k4), mark.time=TRUE, col=1:4,
         main="Kaplan-Meier Survival Curve by survClust (k=4)",
         xlab="Survival Time", ylab="Probability of Survival")
    legend("bottomleft", legend=paste("Cluster", 1:4), col=1:4, lty=1)
    dev.off()
    
    print("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_SURVCLUST_INTEGRATIVE_MULTI_OMIC_CLUSTERING":',
        paste0('    survClust: ', as.character(packageVersion('survClust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_integrative_multi_omic_clustering.csv versions.yml
    """
}

workflow BIOC_SURVCLUST_INTEGRATIVE_MULTI_OMIC_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ uvm_dat, uvm_survdat ] ]

    main:
    BIOC_SURVCLUST_INTEGRATIVE_MULTI_OMIC_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_SURVCLUST_INTEGRATIVE_MULTI_OMIC_CLUSTERING.out.tables
    plots    = BIOC_SURVCLUST_INTEGRATIVE_MULTI_OMIC_CLUSTERING.out.plots
    objects  = BIOC_SURVCLUST_INTEGRATIVE_MULTI_OMIC_CLUSTERING.out.objects
    versions = BIOC_SURVCLUST_INTEGRATIVE_MULTI_OMIC_CLUSTERING.out.versions
}
