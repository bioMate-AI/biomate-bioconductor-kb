#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vsclust — standard_matrix_workflow
// Run variance-sensitive clustering on standard quantitative omics data matrices with replicates, followed by functional enrichment analysis.
// Input: protein_expressions
// Container: quay.io/biocontainers/bioconductor-vsclust:1.12.0--r45ha27e39d_0
// R packages: clusterProfiler, matrixStats, vsclust
// Bioconductor: 3.20 | R: 4.4
// Requires: clusterProfiler, matrixStats, vsclust
// Visualizations: dot plot, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare the data matrix and estimate individual feature variances using PrepareForVSClust
//  * 2. [Core Analysis] Estimate the optimal number of clusters using estimClustNum and optimalClustNum
//  * 3. [Core Analysis] Run variance-sensitive clustering using runClustWrapper
//  * 4. [Core Analysis] Perform functional enrichment analysis on the resulting clusters using runFuncEnrich

nextflow.enable.dsl = 2

process BIOC_VSCLUST_STANDARD_MATRIX_WORKFLOW {
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
    .bm_deps <- c("clusterProfiler", "matrixStats", "vsclust")
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
        library(vsclust)
        library(matrixStats)
        library(clusterProfiler)
        
        # Define parameters
        Experiment <- "ProtExample" 
        NumReps <- 3  
        isPaired <- FALSE
        cores <- 1 
        PreSetNumClustVSClust <- 0 
        PreSetNumClustStand <- 0 
        maxClust <- 10 
        
        # Read user input file from the working directory
        # The pipeline expects a file named 'protein_expressions' with CSV, TSV, or TXT extension
        if (file.exists("protein_expressions.csv")) {
          dat <- read.csv("protein_expressions.csv", row.names = 1, check.names = FALSE)
        } else if (file.exists("protein_expressions.tsv")) {
          dat <- read.delim("protein_expressions.tsv", row.names = 1, check.names = FALSE)
        } else if (file.exists("protein_expressions.txt")) {
          dat <- read.table("protein_expressions.txt", header = TRUE, row.names = 1, check.names = FALSE)
        } else {
          stop("Required input file 'protein_expressions' (CSV/TSV/TXT) not found in the working directory.")
        }
        
        # Convert to matrix if necessary
        dat <- as.matrix(dat)
        
        # Ensure data is strictly numeric
        mode(dat) <- "numeric"
        
        # Calculate NumCond dynamically based on the number of columns and NumReps
        if (ncol(dat) %% NumReps != 0) {
          stop("The number of columns in the dataset is not a multiple of NumReps (", NumReps, ").")
        }
        NumCond <- as.integer(ncol(dat) / NumReps)
        
        #### Running statistical analysis and estimation of individual variances
        statOut <- PrepareForVSClust(dat, NumReps, NumCond, isPaired, TRUE)
        
        dat <- statOut\$dat
        Sds <- dat[, ncol(dat)]
        cat(paste("Features:", nrow(dat), "\nMissing values:",
                  sum(is.na(dat)), "\nMedian standard deviations:",
                  round(median(Sds, na.rm = TRUE), digits = 3), "\n"))
        
        ## Write statistical output into file 
        write.csv(statOut\$statFileOut,
                  paste("", Experiment, "statFileOut.csv", sep = ""))
        
        #### Estimate number of clusters with maxClust as maximum number clusters 
        #### to run the estimation with
        ClustInd <- estimClustNum(dat, maxClust = maxClust, scaling = "standardize", cores = cores)
        
        #### Use estimate cluster number or use own
        if (PreSetNumClustVSClust == 0) {
          PreSetNumClustVSClust <- optimalClustNum(ClustInd)
        }
        if (PreSetNumClustStand == 0) {
          PreSetNumClustStand <- optimalClustNum(ClustInd, method = "FCM")
        }
        
        #### Visualize and save cluster estimation plot
        pdf(paste0(Experiment, "_estimClust_plot.pdf"))
        estimClust.plot(ClustInd)
        dev.off()
        
        #### Run clustering (VSClust)
        ClustOut <- runClustWrapper(dat, 
                                    PreSetNumClustVSClust, 
                                    NULL, 
                                    VSClust = TRUE, 
                                    scaling = "standardize",
                                    cores = cores)
        Bestcl <- ClustOut\$Bestcl
        VSClust_cl <- Bestcl
        
        ## Write clustering results (VSClust)
        write.csv(data.frame(cluster = Bestcl\$cluster,
                             ClustOut\$outFileClust,
                             isClusterMember = rowMaxs(Bestcl\$membership) > 0.5,
                             maxMembership = rowMaxs(Bestcl\$membership),
                             Bestcl\$membership), 
                  paste(Experiment, 
                        "FCMVarMResults_", 
                        Sys.Date(), 
                        ".csv", 
                        sep = ""))
        
        ## Write coordinates of cluster centroids (VSClust)
        write.csv(Bestcl\$centers, 
                  paste(Experiment,
                        "FCMVarMResultsCentroids_",
                        Sys.Date(), 
                        ".csv", 
                        sep = ""))
        
        #### Run standard FCM clustering for comparison
        ClustOut2 <- runClustWrapper(dat, 
                                     PreSetNumClustStand, 
                                     NULL, 
                                     VSClust = FALSE, 
                                     scaling = "standardize", 
                                     cores = cores)
        Bestcl2 <- ClustOut2\$Bestcl
        
        ## Write clustering results (standard FCM)
        write.csv(data.frame(cluster = Bestcl2\$cluster,
                             ClustOut2\$outFileClust,
                             isClusterMember = rowMaxs(Bestcl2\$membership) > 0.5,
                             maxMembership = rowMaxs(Bestcl2\$membership),
                             Bestcl2\$membership), 
                  paste(Experiment, 
                        "FCMResults_", 
                        Sys.Date(), 
                        ".csv", 
                        sep = ""))
        
        ## Write coordinates of cluster centroids (standard FCM)
        write.csv(Bestcl2\$centers, 
                  paste(Experiment,
                        "FCMResultsCentroids_", 
                        Sys.Date(),
                        ".csv", 
                        sep = ""))
        
        # Save clustering objects as RDS for downstream analysis
        saveRDS(ClustOut, file = paste0(Experiment, "_VSClust_output.rds"))
        saveRDS(ClustOut2, file = paste0(Experiment, "_FCM_output.rds"))
        
        # Functional enrichment
        # Note: requires network access to the STRING API; skipped when unavailable
        ClustEnriched <- tryCatch(
            runFuncEnrich(VSClust_cl, infosource = "KEGG"),
            error = function(e) {
                message("STRING enrichment unavailable: ", conditionMessage(e))
                NULL
            }
        )
        
        if (!is.null(ClustEnriched)) {
            # Take the reduced version of the enrichment (redFuncs), not the full one (fullFuncs)
            redClustEnriched <- ClustEnriched\$redFuncs
            
            # Save enrichment results
            saveRDS(ClustEnriched, file = paste0(Experiment, "_ClustEnriched.rds"))
            
            # Plot the top 10 most enriched KEGG pathways
            pdf(paste0(Experiment, "_KEGG_enrichment_dotplot.pdf"), width = 10, height = 8)
            print(dotplot(redClustEnriched, showCategory = 10, title = "KEGG enrichment", size = "count"))
            dev.off()
        } else {
            message("Functional enrichment skipped or failed.")
        }
        
        cat("Pipeline completed successfully.\n")

    writeLines(c(
        '"BIOC_VSCLUST_STANDARD_MATRIX_WORKFLOW":',
        paste0('    vsclust: ', as.character(packageVersion('vsclust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_matrix_workflow.csv versions.yml
    """
}

workflow BIOC_VSCLUST_STANDARD_MATRIX_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ protein_expressions ] ]

    main:
    BIOC_VSCLUST_STANDARD_MATRIX_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_VSCLUST_STANDARD_MATRIX_WORKFLOW.out.tables
    plots    = BIOC_VSCLUST_STANDARD_MATRIX_WORKFLOW.out.plots
    objects  = BIOC_VSCLUST_STANDARD_MATRIX_WORKFLOW.out.objects
    versions = BIOC_VSCLUST_STANDARD_MATRIX_WORKFLOW.out.versions
}
