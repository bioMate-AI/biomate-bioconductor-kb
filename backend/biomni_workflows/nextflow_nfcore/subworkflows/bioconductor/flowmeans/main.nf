#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowMeans — flow_cytometry_gating
// Identify and visualize cell populations in flow cytometry data using non-parametric clustering and change point detection.
// Input: flow_data.csv
// Container: quay.io/biocontainers/bioconductor-flowmeans:1.70.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowMeans
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and input data
//  * 2. [Core Analysis] Run the flowMeans clustering algorithm on specified marker channels
//  * 3. [Visualization & Output] Plot the minimum distances between merged clusters
//  * 4. [Visualization & Output] Detect the optimal number of clusters using changepointDetection and plot the change point
//  * 5. [Visualization & Output] Visualize the final cluster memberships in 2D and multi-dimensional plots

nextflow.enable.dsl = 2

process BIOC_FLOWMEANS_FLOW_CYTOMETRY_GATING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("flowMeans")
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
        
        # 1. Load the package and input data
        library(flowMeans)
        
        if (!file.exists("flow_data.csv")) {
          stop("Error: 'flow_data.csv' not found in the working directory.")
        }
        
        # Read the user-provided flow cytometry data
        df <- read.csv("flow_data.csv", check.names = FALSE)
        x <- as.matrix(df)
        
        # 2. Run the flowMeans clustering algorithm on specified marker channels
        res <- flowMeans(x, varNames=colnames(x), MaxN=10)
        
        # Open PDF device to save all visualizations
        pdf("flowMeans_plots.pdf", width=8, height=8)
        
        # 3. Plot the minimum distances between merged clusters
        plot(x[, 1:min(2, ncol(x))], col=res@Labels[[1]], pch=20)
        plot(res@Mins, xlab='Iteration', ylab='Distance')
        
        # 4. Detect the optimal number of clusters using changepointDetection and plot the change point
        plot(res@Mins, xlab=' ', ylab=' ', xlim=c(1, res@MaxN), ylim=c(0, max(res@Mins)))
        ft<-changepointDetection(res@Mins)
        abline(ft\$l1)
        abline(ft\$l2)
        par(new=TRUE)
        plot(ft\$MinIndex+1, res@Mins[ft\$MinIndex+1], col='red', xlab='Iteration', ylab='Distance', xlim=c(1, res@MaxN), ylim=c(0, max(res@Mins)), pch=19)
        
        # 5. Visualize the final cluster memberships in 2D and multi-dimensional plots
        plot(x, res, colnames(x)[1:min(2, ncol(x))])
        plot(x, res, colnames(x), pch='.')
        
        dev.off()
        
        # Save meaningful results to files
        saveRDS(res, "flowMeans_result.rds")
        
        # Save final cluster labels
        labels_df <- data.frame(
          RowID = seq_len(nrow(x)),
          Cluster = res@Label
        )
        write.csv(labels_df, "cluster_labels.csv", row.names = FALSE)
        
        # Save changepoint detection summary
        changepoint_df <- data.frame(
          MinIndex = ft\$MinIndex,
          OptimalNumberOfClusters = ft\$MinIndex + 1
        )
        write.csv(changepoint_df, "changepoint_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_FLOWMEANS_FLOW_CYTOMETRY_GATING":',
        paste0('    flowMeans: ', as.character(packageVersion('flowMeans')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flow_cytometry_gating.csv versions.yml
    """
}

workflow BIOC_FLOWMEANS_FLOW_CYTOMETRY_GATING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ flow_data.csv ] ]

    main:
    BIOC_FLOWMEANS_FLOW_CYTOMETRY_GATING(ch_input)

    emit:
    tables   = BIOC_FLOWMEANS_FLOW_CYTOMETRY_GATING.out.tables
    plots    = BIOC_FLOWMEANS_FLOW_CYTOMETRY_GATING.out.plots
    objects  = BIOC_FLOWMEANS_FLOW_CYTOMETRY_GATING.out.objects
    versions = BIOC_FLOWMEANS_FLOW_CYTOMETRY_GATING.out.versions
}
