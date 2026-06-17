#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowPeaks — flowframe_clustering
// Cluster flow cytometry data imported as a flowFrame object from the flowCore package.
// Input: 0877408774.B08
// Container: quay.io/biocontainers/bioconductor-flowpeaks:1.56.0--r45h1ca3914_0
// R packages: flowCore, flowPeaks
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowPeaks
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load flowCore and read the FCS file into a flowFrame
//  * 2. [Core Analysis] Extract and transform the expression matrix using asinh
//  * 3. [Core Analysis] Run flowPeaks clustering on the transformed expression data
//  * 4. [Visualization & Output] Plot the clustering results

nextflow.enable.dsl = 2

process BIOC_FLOWPEAKS_FLOWFRAME_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    library(flowCore)
    library(flowPeaks)
    
    # Define input file
    input_file <- "0877408774.B08"
    
    # Verify input file existence
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # 1. Load flowCore and read the FCS file into a flowFrame
    samp <- read.FCS(input_file)
    
    # 2 & 3. Extract and transform the expression matrix using asinh, 
    # and run flowPeaks clustering on the transformed expression data.
    # (Faithfully reproducing the documented function calls and arguments)
    fp.z <- flowPeaks(asinh(samp@exprs[, 3:4]))
    
    # 4. Plot the clustering results to a PDF file
    pdf("flowPeaks_plot.pdf", width = 8, height = 8)
    plot(fp.z)
    dev.off()
    
    # Save the flowPeaks clustering object as an RDS file
    saveRDS(fp.z, "flowPeaks_results.rds")
    
    # Export the transformed expression data along with cluster assignments to a CSV file
    transformed_data <- asinh(samp@exprs[, 3:4])
    output_data <- data.frame(
      Channel_3 = transformed_data[, 1],
      Channel_4 = transformed_data[, 2],
      Cluster = fp.z\$peaks.cluster
    )
    write.csv(output_data, "clustering_results.csv", row.names = FALSE)
    
    cat("Workflow completed successfully.\n")
    cat("Outputs generated:\n")
    cat("- flowPeaks_plot.pdf (Clustering visualization)\n")
    cat("- flowPeaks_results.rds (Serialized flowPeaks object)\n")
    cat("- clustering_results.csv (Transformed expression data with cluster assignments)\n")

    writeLines(c(
        '"BIOC_FLOWPEAKS_FLOWFRAME_CLUSTERING":',
        paste0('    flowPeaks: ', as.character(packageVersion('flowPeaks')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowframe_clustering.csv versions.yml
    """
}

workflow BIOC_FLOWPEAKS_FLOWFRAME_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ 0877408774.B08 ] ]

    main:
    BIOC_FLOWPEAKS_FLOWFRAME_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_FLOWPEAKS_FLOWFRAME_CLUSTERING.out.tables
    plots    = BIOC_FLOWPEAKS_FLOWFRAME_CLUSTERING.out.plots
    objects  = BIOC_FLOWPEAKS_FLOWFRAME_CLUSTERING.out.objects
    versions = BIOC_FLOWPEAKS_FLOWFRAME_CLUSTERING.out.versions
}
