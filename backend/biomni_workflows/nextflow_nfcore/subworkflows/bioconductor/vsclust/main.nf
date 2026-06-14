#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vsclust — bioconductor_object_workflow
// Run variance-sensitive clustering on quantitative omics data stored in Bioconductor objects (such as MultiAssayExperiment or SummarizedExperiment).
// Input: miniACC
// Container: quay.io/biocontainers/bioconductor-vsclust:1.12.0--r45ha27e39d_0
// R packages: clusterProfiler, matrixStats, MultiAssayExperiment, vsclust
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiAssayExperiment, matrixStats, vsclust
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Log-transform and normalize assay data
//  * 2. [Input & Preparation] Prepare the Bioconductor object for clustering using PrepareSEForVSClust
//  * 3. [Core Analysis] Estimate the optimal number of clusters using estimClustNum and optimalClustNum
//  * 4. [Core Analysis] Run variance-sensitive clustering using runClustWrapper

nextflow.enable.dsl = 2

process BIOC_VSCLUST_BIOCONDUCTOR_OBJECT_WORKFLOW {
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
    .bm_deps <- c("clusterProfiler", "matrixStats", "MultiAssayExperiment", "vsclust", "SummarizedExperiment")
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
    librar    library(SummarizedExperiment)
y(MultiAssayExperiment)
    library(vsclust)
    library(matrixStats)
    
    # 1. Read User Input File
    if (file.exists("miniACC")) {
      miniACC <- readRDS("miniACC")
    } else if (file.exists("miniACC.rds")) {
      miniACC <- readRDS("miniACC.rds")
    } else {
      stop("Required input file 'miniACC' or 'miniACC.rds' not found in the working directory.")
    }
    
    # 2. Initialization and Parameters
    Experiment <- "miniACC" 
    isPaired <- FALSE
    cores <- 1 
    PreSetNumClustVSClust <- 0 
    PreSetNumClustStand <- 0 
    maxClust <- 10 
    
    # 3. Log-transformation and normalization of assay data
    logminiACC <- log2(assays(miniACC)\$RNASeq2GeneNorm)
    logminiACC[!is.finite(logminiACC)] <- NA
    
    # Normalize to median
    logminiACC <- t(t(logminiACC) - apply(logminiACC, 2, median, na.rm=TRUE))
    
    # Add normalized assay back to MultiAssayExperiment
    miniACC2 <- c(miniACC, log2rnaseq = logminiACC, mapFrom=1L)
    
    # Save boxplot of normalized data
    pdf("boxplot_logminiACC.pdf")
    boxplot(logminiACC, main="Log2 Normalized RNASeq2GeneNorm")
    dev.off()
    
    # 4. Run statistical analysis and estimation of individual variances
    statOut <- PrepareSEForVSClust(miniACC2, "log2rnaseq", 
                                   coldatname = "OncoSign", 
                                   isPaired=isPaired, isStat=TRUE)
    
    # Save intermediate statistical output
    saveRDS(statOut, "statOut.rds")
    
    # 5. Estimate optimal number of clusters
    ClustInd <- estimClustNum(statOut\$dat, maxClust=maxClust, cores=cores)
    
    # Determine optimal cluster numbers
    if (PreSetNumClustVSClust == 0) {
      PreSetNumClustVSClust <- optimalClustNum(ClustInd)
    }
    if (PreSetNumClustStand == 0) {
      PreSetNumClustStand <- optimalClustNum(ClustInd, method="FCM")
    }
    
    # Save cluster estimation plot
    pdf("estimClust_plot.pdf")
    estimClust.plot(ClustInd)
    dev.off()
    
    # 6. Run variance-sensitive clustering (VSClust)
    ClustOut <- runClustWrapper(statOut\$dat, 
                                PreSetNumClustVSClust, NULL, 
                                VSClust=TRUE,
                                cores=cores)
    Bestcl <- ClustOut\$Bestcl
    VSClust_cl <- Bestcl
    
    # 7. Save Outputs
    saveRDS(ClustOut, "ClustOut.rds")
    
    # Write clustering results
    write.csv(data.frame(cluster=Bestcl\$cluster,
                         ClustOut\$outFileClust,
                         isClusterMember=rowMaxs(Bestcl\$membership) > 0.5,
                         maxMembership=rowMaxs(Bestcl\$membership),
                         Bestcl\$membership), 
              paste(Experiment, "_FCMVarMResults.csv", sep=""),
              row.names=TRUE)
    
    # Write coordinates of cluster centroids
    write.csv(Bestcl\$centers, 
              paste(Experiment, "_FCMVarMResultsCentroids.csv", sep=""),
              row.names=TRUE)

    writeLines(c(
        '"BIOC_VSCLUST_BIOCONDUCTOR_OBJECT_WORKFLOW":',
        paste0('    vsclust: ', as.character(packageVersion('vsclust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bioconductor_object_workflow.csv versions.yml
    """
}

workflow BIOC_VSCLUST_BIOCONDUCTOR_OBJECT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ miniACC ] ]

    main:
    BIOC_VSCLUST_BIOCONDUCTOR_OBJECT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_VSCLUST_BIOCONDUCTOR_OBJECT_WORKFLOW.out.tables
    plots    = BIOC_VSCLUST_BIOCONDUCTOR_OBJECT_WORKFLOW.out.plots
    objects  = BIOC_VSCLUST_BIOCONDUCTOR_OBJECT_WORKFLOW.out.objects
    versions = BIOC_VSCLUST_BIOCONDUCTOR_OBJECT_WORKFLOW.out.versions
}
