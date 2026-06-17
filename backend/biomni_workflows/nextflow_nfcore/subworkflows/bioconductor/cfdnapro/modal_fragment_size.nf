#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cfDNAPro — modal_fragment_size
// Calculate and visualize the modal fragment size of each sample using bar charts or stacked bar charts.
// Input: groups_picard
// Container: quay.io/biocontainers/bioconductor-cfdnapro:1.16.1--r45hdfd78af_0
// R packages: cfDNAPro, dplyr, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: cfDNAPro, dplyr, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate modal fragment sizes using callMode
//  * 2. [Visualization & Output] Plot modal sizes as a bar chart using plotMode or as a stacked bar chart using plotModeSummary

nextflow.enable.dsl = 2

process BIOC_CFDNAPRO_MODAL_FRAGMENT_SIZE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("cfDNAPro", "dplyr", "ggplot2")
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
    library(cfDNAPro)
    library(dplyr)
    library(ggplot2)
    
    # Define the input path
    data_path <- "groups_picard"
    
    # Validate input directory existence
    if (!dir.exists(data_path)) {
      stop(paste("Error: Input directory '", data_path, "' does not exist in the current working directory.", sep = ""))
    }
    
    # Dynamically retrieve cohort names from the sub-folders to set the order
    order <- list.dirs(data_path, full.names = FALSE, recursive = FALSE)
    if (length(order) == 0) {
      stop(paste("Error: No cohort sub-directories found in '", data_path, "'.", sep = ""))
    }
    
    # 1. Calculate modal fragment sizes and export the raw data
    message("Calculating modal fragment sizes...")
    modes_df <- callMode(data_path)
    write.csv(modes_df, "modal_fragment_sizes.csv", row.names = FALSE)
    
    # 2. Generate and save the modal size bar chart
    message("Generating modal size bar chart...")
    mode_bin <- callMode(data_path) %>% plotMode(order=order,hline = c(167,111,81))
    ggplot2::ggsave("modal_size_bar_chart.pdf", plot = mode_bin, width = 8, height = 6)
    
    # 3. Generate, modify, and save the stacked bar chart
    message("Generating stacked bar chart...")
    mode_stacked <- 
      callMode(data_path) %>% 
      plotModeSummary(order=order,
                      mode_partition = list(c(166,167)))
    
    # Modify the plot using ggplot syntax as shown in the documentation
    mode_stacked <- mode_stacked + theme(legend.position = "top")
    ggplot2::ggsave("modal_size_stacked_bar_chart.pdf", plot = mode_stacked, width = 8, height = 6)
    
    message("Workflow complete. Outputs saved: 'modal_fragment_sizes.csv', 'modal_size_bar_chart.pdf', and 'modal_size_stacked_bar_chart.pdf'.")

    writeLines(c(
        '"BIOC_CFDNAPRO_MODAL_FRAGMENT_SIZE":',
        paste0('    cfDNAPro: ', as.character(packageVersion('cfDNAPro')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_modal_fragment_size.csv versions.yml
    """
}

workflow BIOC_CFDNAPRO_MODAL_FRAGMENT_SIZE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ groups_picard ] ]

    main:
    BIOC_CFDNAPRO_MODAL_FRAGMENT_SIZE(ch_input)

    emit:
    tables   = BIOC_CFDNAPRO_MODAL_FRAGMENT_SIZE.out.tables
    plots    = BIOC_CFDNAPRO_MODAL_FRAGMENT_SIZE.out.plots
    objects  = BIOC_CFDNAPRO_MODAL_FRAGMENT_SIZE.out.objects
    versions = BIOC_CFDNAPRO_MODAL_FRAGMENT_SIZE.out.versions
}
