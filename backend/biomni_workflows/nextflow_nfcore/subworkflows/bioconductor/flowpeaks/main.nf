#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowPeaks — matrix_clustering_and_evaluation
// Cluster a numeric matrix of flow cytometry data, visualize the results in 2D/pairwise plots, evaluate cluster performance against a gold standard, and identify 
// Input: barcode, barcode.cid
// Container: quay.io/biocontainers/bioconductor-flowpeaks:1.56.0--r45h1ca3914_0
// R packages: flowCore, flowPeaks
// Bioconductor: 3.20 | R: 4.4
// Requires: flowPeaks
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and data
//  * 2. [Core Analysis] Run flowPeaks clustering on the full matrix
//  * 3. [Visualization & Output] Plot 2D and pairwise projections of the clustering results
//  * 4. [Core Analysis] Run flowPeaks clustering on selected dimensions
//  * 5. [Core Analysis] Evaluate clustering performance against a gold standard using evalCluster
//  * 6. [Visualization & Output] Identify and assign outliers using assign.flowPeaks and re-plot

nextflow.enable.dsl = 2

process BIOC_FLOWPEAKS_MATRIX_CLUSTERING_AND_EVALUATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("flowCore", "flowPeaks")
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
    
    # Load the required package
    library(flowPeaks)
    
    # ==========================================
    # 1. Load the package and data
    # ==========================================
    
    # Robustly read the 'barcode' input file from the working directory
    if (file.exists("barcode.rds")) {
      barcode <- readRDS("barcode.rds")
    } else if (file.exists("barcode.csv")) {
      barcode <- read.csv("barcode.csv", header = TRUE)
    } else if (file.exists("barcode.tsv")) {
      barcode <- read.delim("barcode.tsv", header = TRUE)
    } else if (file.exists("barcode")) {
      barcode <- tryCatch(readRDS("barcode"), error = function(e) {
        tryCatch(read.table("barcode", header = TRUE), error = function(e2) {
          read.csv("barcode", header = TRUE)
        })
      })
    } else {
      stop("Required input file 'barcode' not found in the working directory.")
    }
    
    # Ensure barcode is a numeric matrix
    barcode <- as.matrix(barcode)
    
    # Robustly read the 'barcode.cid' input file from the working directory
    if (file.exists("barcode.cid.rds")) {
      barcode.cid <- readRDS("barcode.cid.rds")
    } else if (file.exists("barcode.cid.csv")) {
      barcode.cid <- read.csv("barcode.cid.csv", header = FALSE)[[1]]
    } else if (file.exists("barcode.cid.tsv")) {
      barcode.cid <- read.delim("barcode.cid.tsv", header = FALSE)[[1]]
    } else if (file.exists("barcode.cid")) {
      barcode.cid <- tryCatch(readRDS("barcode.cid"), error = function(e) {
        tryCatch(scan("barcode.cid", quiet = TRUE), error = function(e2) {
          read.csv("barcode.cid", header = FALSE)[[1]]
        })
      })
    } else {
      stop("Required input file 'barcode.cid' not found in the working directory.")
    }
    
    # Ensure barcode.cid is a vector
    barcode.cid <- as.vector(barcode.cid)
    
    # Display summary of the input data
    summary(barcode)
    
    # ==========================================
    # 2. Run flowPeaks clustering on the full matrix
    # ==========================================
    fp<-flowPeaks(barcode)
    
    # Save the full clustering object
    saveRDS(fp, "fp_full.rds")
    
    # ==========================================
    # 3. Plot 2D and pairwise projections of the clustering results
    # ==========================================
    pdf("plot_fp_1_3.pdf", width=7, height=7)
    plot(fp,idx=c(1,3))
    dev.off()
    
    pdf("plot_fp_pairwise.pdf", width=10, height=10)
    par(mfrow=c(2,2))
    plot(fp,idx=c(1,2,3))
    dev.off()
    
    # ==========================================
    # 4. Run flowPeaks clustering on selected dimensions
    # ==========================================
    fp2<-flowPeaks(barcode[,c(1,3)])
    
    # Save the selected dimensions clustering object
    saveRDS(fp2, "fp_selected.rds")
    
    pdf("plot_fp2.pdf", width=7, height=7)
    plot(fp2)
    dev.off()
    
    # ==========================================
    # 5. Evaluate clustering performance against a gold standard
    # ==========================================
    v_measure <- evalCluster(barcode.cid,fp2\$peaks.cluster,method="Vmeasure")
    
    # Save evaluation metric to a CSV file
    write.csv(data.frame(Metric="Vmeasure", Value=v_measure), 
              "evaluation_metric.csv", row.names=FALSE)
    
    # ==========================================
    # 6. Identify and assign outliers and re-plot
    # ==========================================
    fpc<-assign.flowPeaks(fp2,fp2\$x)
    
    # Save outlier assignments to a CSV file
    write.csv(data.frame(Cell_ID=1:length(fpc), Cluster_Assignment=fpc), 
              "outlier_assignments.csv", row.names=FALSE)
    
    pdf("plot_fp2_outliers.pdf", width=7, height=7)
    plot(fp2,classlab=fpc,drawboundary=FALSE,
      drawvor=FALSE,drawkmeans=FALSE,drawlab=TRUE)
    dev.off()

    writeLines(c(
        '"BIOC_FLOWPEAKS_MATRIX_CLUSTERING_AND_EVALUATION":',
        paste0('    flowPeaks: ', as.character(packageVersion('flowPeaks')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrix_clustering_and_evaluation.csv versions.yml
    """
}

workflow BIOC_FLOWPEAKS_MATRIX_CLUSTERING_AND_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ barcode, barcode.cid ] ]

    main:
    BIOC_FLOWPEAKS_MATRIX_CLUSTERING_AND_EVALUATION(ch_input)

    emit:
    tables   = BIOC_FLOWPEAKS_MATRIX_CLUSTERING_AND_EVALUATION.out.tables
    plots    = BIOC_FLOWPEAKS_MATRIX_CLUSTERING_AND_EVALUATION.out.plots
    objects  = BIOC_FLOWPEAKS_MATRIX_CLUSTERING_AND_EVALUATION.out.objects
    versions = BIOC_FLOWPEAKS_MATRIX_CLUSTERING_AND_EVALUATION.out.versions
}
