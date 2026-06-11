#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: survClust — single_omic_clustering
// Perform supervised clustering on a single genomic data type (e.g., mutation data alone) weighted by survival outcome.
// Input: uvm_mut_dat, uvm_survdat
// Container: quay.io/biocontainers/bioconductor-survclust:1.4.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, survClust, survival
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load User Input Files
//  * 2. [Visualization & Output] Define Cross-Validation Helper Function
//  * 3. [Visualization & Output] Execute Cross-Validation across k = 2 to 7
//  * 4. [Visualization & Output] Summarize and Plot Cross-Validation Performance Metrics
//  * 5. [Visualization & Output] Consolidate Cluster Assignments and Perform Survival

nextflow.enable.dsl = 2

process BIOC_SURVCLUST_SINGLE_OMIC_CLUSTERING {
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
    library(survClust)
    library(survival)
    library(BiocParallel)
    
    # -----------------------------------------------------------------------------
    # --- Load User Input Files ---
    # -----------------------------------------------------------------------------
    # The pipeline reads uvm_mut_dat and uvm_survdat from the working directory.
    # It supports both RDS (preferred for lists/matrices) and CSV formats.
    
    if (file.exists("uvm_mut_dat.rds")) {
        uvm_mut_dat <- readRDS("uvm_mut_dat.rds")
    } else if (file.exists("uvm_mut_dat.csv")) {
        mut_mat <- as.matrix(read.csv("uvm_mut_dat.csv", row.names = 1))
        uvm_mut_dat <- list(mut_mat)
    } else {
        stop("Error: Required input file 'uvm_mut_dat.rds' or 'uvm_mut_dat.csv' not found in the working directory.")
    }
    
    if (file.exists("uvm_survdat.rds")) {
        uvm_survdat <- readRDS("uvm_survdat.rds")
    } else if (file.exists("uvm_survdat.csv")) {
        uvm_survdat <- as.matrix(read.csv("uvm_survdat.csv", row.names = 1))
    } else {
        stop("Error: Required input file 'uvm_survdat.rds' or 'uvm_survdat.csv' not found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # --- Define Cross-Validation Helper Function ---
    # -----------------------------------------------------------------------------
    cv_rounds <- 10
    
    cvrounds_mut <- function(kk){
        this.fold<-3
        fit<-list()
        for (i in seq_len(cv_rounds)){
            fit[[i]] <- cv_survclust(uvm_mut_dat, uvm_survdat,kk,this.fold, type="mut")
            print(paste0("finished ", i, " rounds for k= ", kk))
        }
        return(fit)
    }
    
    # -----------------------------------------------------------------------------
    # --- Execute Cross-Validation across k = 2 to 7 ---
    # -----------------------------------------------------------------------------
    # Run cross-validation using parallel processing
    uvm_mut_cv.fit <- bplapply(2:7, cvrounds_mut)
    
    # Save the raw cross-validation fit object
    saveRDS(uvm_mut_cv.fit, "uvm_mut_cv_fit.rds")
    
    # -----------------------------------------------------------------------------
    # --- Summarize and Plot Cross-Validation Performance Metrics ---
    # -----------------------------------------------------------------------------
    ss_stats <- getStats(uvm_mut_cv.fit, kk=7, cvr=10)
    saveRDS(ss_stats, "ss_stats.rds")
    
    # Plot and save the summarized metrics
    pdf("survClust_stats_plot.pdf", width = 8, height = 8)
    plotStats(ss_stats, 2:7)
    dev.off()
    
    # -----------------------------------------------------------------------------
    # --- Consolidate Cluster Assignments and Perform Survival ---
    # -----------------------------------------------------------------------------
    # Compute the single-platform weighted distance matrix and consolidate cluster assignments
    k4 <- cv_voting(uvm_mut_cv.fit, getDist(uvm_mut_dat, uvm_survdat), pick_k=4)
    
    # Save cluster assignments to a CSV file
    cluster_df <- data.frame(Sample = names(k4), Cluster = k4)
    write.csv(cluster_df, "cluster_assignments_k4.csv", row.names = FALSE)
    
    # Perform survival analysis and save the Kaplan-Meier plot
    pdf("km_plot_k4.pdf", width = 6, height = 6)
    plot(survfit(Surv(uvm_survdat[,1], uvm_survdat[,2]) ~ k4), mark.time=TRUE, col=2:5)
    dev.off()

    writeLines(c(
        '"BIOC_SURVCLUST_SINGLE_OMIC_CLUSTERING":',
        paste0('    survClust: ', as.character(packageVersion('survClust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_omic_clustering.csv versions.yml
    """
}

workflow BIOC_SURVCLUST_SINGLE_OMIC_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ uvm_mut_dat, uvm_survdat ] ]

    main:
    BIOC_SURVCLUST_SINGLE_OMIC_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_SURVCLUST_SINGLE_OMIC_CLUSTERING.out.tables
    plots    = BIOC_SURVCLUST_SINGLE_OMIC_CLUSTERING.out.plots
    objects  = BIOC_SURVCLUST_SINGLE_OMIC_CLUSTERING.out.objects
    versions = BIOC_SURVCLUST_SINGLE_OMIC_CLUSTERING.out.versions
}
