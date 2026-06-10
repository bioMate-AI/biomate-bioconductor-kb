#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cfDNAPro — inter_peak_valley_distance
// Quantify the 10 bp periodic oscillation by calculating and plotting inter-peak and inter-valley distances.
// Input: groups_picard
// Container: quay.io/biocontainers/bioconductor-cfdnapro:1.16.1--r45hdfd78af_0
// Requires: cfDNAPro, dplyr, ggplot2, magrittr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate inter-peak distances using callPeakDistance
//  * 2. [Core Analysis] Calculate inter-valley distances using callValleyDistance
//  * 3. [Visualization & Output] Plot distances using plotPeakDistance and plotValleyDistance

nextflow.enable.dsl = 2

process BIOC_CFDNAPRO_INTER_PEAK_VALLEY_DISTANCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("cfDNAPro", "dplyr", "ggplot2", "magrittr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(cfDNAPro)
    library(dplyr)
    library(magrittr)
    library(ggplot2)
    
    # Define input path pointing to the user-provided directory
    data_path <- "groups_picard"
    
    # Verify that the input directory exists
    if (!dir.exists(data_path)) {
      stop(paste("Error: Input directory 'groups_picard' not found in the current working directory:", getwd()))
    }
    
    # Define the cohort order dynamically based on the sub-folders in the data path
    order <- list.dirs(data_path, full.names = FALSE, recursive = FALSE)
    
    # ==========================================
    # 1. Calculate and Plot Inter-Peak Distances
    # ==========================================
    
    # Calculate the raw peak distances
    inter_peak_data <- callPeakDistance(path = data_path, limit = c(50, 135))
    
    # Save the raw peak distance data
    write.csv(inter_peak_data, "inter_peak_distances.csv", row.names = FALSE)
    saveRDS(inter_peak_data, "inter_peak_distances.rds")
    
    # Generate the inter-peak distance plot using the exact documented pipeline
    inter_peak_dist <- inter_peak_data %>%
      plotPeakDistance(order = order)
    
    # Save the peak distance plot
    ggsave("inter_peak_distance_plot.pdf", plot = inter_peak_dist, width = 8, height = 6)
    
    
    # ============================================
    # 2. Calculate and Plot Inter-Valley Distances
    # ============================================
    
    # Calculate the raw valley distances
    inter_valley_data <- callValleyDistance(path = data_path, limit = c(50, 135))
    
    # Save the raw valley distance data
    write.csv(inter_valley_data, "inter_valley_distances.csv", row.names = FALSE)
    saveRDS(inter_valley_data, "inter_valley_distances.rds")
    
    # Generate the inter-valley distance plot using the exact documented pipeline
    inter_valley_dist <- inter_valley_data %>%
      plotValleyDistance(order = order)
    
    # Save the valley distance plot
    ggsave("inter_valley_distance_plot.pdf", plot = inter_valley_dist, width = 8, height = 6)
    
    message("Pipeline completed successfully. All outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_CFDNAPRO_INTER_PEAK_VALLEY_DISTANCE":',
        paste0('    cfDNAPro: ', as.character(packageVersion('cfDNAPro')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inter_peak_valley_distance.csv versions.yml
    """
}

workflow BIOC_CFDNAPRO_INTER_PEAK_VALLEY_DISTANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ groups_picard ] ]

    main:
    BIOC_CFDNAPRO_INTER_PEAK_VALLEY_DISTANCE(ch_input)

    emit:
    tables   = BIOC_CFDNAPRO_INTER_PEAK_VALLEY_DISTANCE.out.tables
    plots    = BIOC_CFDNAPRO_INTER_PEAK_VALLEY_DISTANCE.out.plots
    objects  = BIOC_CFDNAPRO_INTER_PEAK_VALLEY_DISTANCE.out.objects
    versions = BIOC_CFDNAPRO_INTER_PEAK_VALLEY_DISTANCE.out.versions
}
