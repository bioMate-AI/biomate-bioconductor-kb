#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SamSPECTRAL — quick_samspectral_clustering
// Run the complete SamSPECTRAL clustering pipeline using the high-level wrapper function on a flow cytometry data matrix.
// Input: flow_data.csv
// Container: quay.io/biocontainers/bioconductor-samspectral:1.64.0--r45h01b2380_0
// R packages: SamSPECTRAL
// Bioconductor: 3.20 | R: 4.4
// Requires: SamSPECTRAL
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and data
//  * 2. [Core Analysis] Run the SamSPECTRAL wrapper function with specified dimensions, normal.sigma, and separation.factor
//  * 3. [Visualization & Output] Calculate cluster frequencies and plot results

nextflow.enable.dsl = 2

process BIOC_SAMSPECTRAL_QUICK_SAMSPECTRAL_CLUSTERING {
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
    .bm_deps <- c("SamSPECTRAL")
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
    
    # Load required library
    library(SamSPECTRAL)
    
    # Set seed for reproducibility
    set.seed(4)
    
    # Read user input
    if (!file.exists("flow_data.csv")) {
      stop("Error: flow_data.csv not found in the working directory.")
    }
    full <- as.matrix(read.csv("flow_data.csv"))
    
    # Run SamSPECTRAL clustering using the exact documented function and arguments
    L <- SamSPECTRAL(full, dimension=c(1,2,3), normal.sigma = 200,
                     separation.factor = 0.39)   
    
    # Open PDF device to save the plot
    pdf("samspectral_plot.pdf", width=7, height=7)
    
    # Plotting and frequency calculation exactly as documented
    plot(full, pch='.', col= L)
    
    frequency <- c()	
    minimum.frequency <- 0.01	
    freq.large <- c()	
    labels <- as.character(unique(L))
    for(label in labels){
      if(!is.na(label)){
        frequency[label] <- length(which(L==label))/length(L)
        if(frequency[label] > minimum.frequency)
          freq.large[label] <- frequency[label]
      }
    }	
    print(frequency)	
    
    legend(x="topleft", as.character(round(freq.large,3)),
           col=names(freq.large), pch=19)
    
    # Close PDF device
    dev.off()
    
    # Save meaningful results to output files
    # 1. Save the cluster labels as an RDS object
    saveRDS(L, "samspectral_labels.rds")
    
    # 2. Save the original data with cluster labels as a CSV
    output_data <- as.data.frame(full)
    output_data\$Cluster <- L
    write.csv(output_data, "clustering_results.csv", row.names = FALSE)
    
    # 3. Save the calculated cluster frequencies as a CSV
    frequency_df <- data.frame(
      Cluster = names(frequency),
      Frequency = as.numeric(frequency),
      stringsAsFactors = FALSE
    )
    write.csv(frequency_df, "cluster_frequencies.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SAMSPECTRAL_QUICK_SAMSPECTRAL_CLUSTERING":',
        paste0('    SamSPECTRAL: ', as.character(packageVersion('SamSPECTRAL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_samspectral_clustering.csv versions.yml
    """
}

workflow BIOC_SAMSPECTRAL_QUICK_SAMSPECTRAL_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ flow_data.csv ] ]

    main:
    BIOC_SAMSPECTRAL_QUICK_SAMSPECTRAL_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_SAMSPECTRAL_QUICK_SAMSPECTRAL_CLUSTERING.out.tables
    plots    = BIOC_SAMSPECTRAL_QUICK_SAMSPECTRAL_CLUSTERING.out.plots
    objects  = BIOC_SAMSPECTRAL_QUICK_SAMSPECTRAL_CLUSTERING.out.objects
    versions = BIOC_SAMSPECTRAL_QUICK_SAMSPECTRAL_CLUSTERING.out.versions
}
