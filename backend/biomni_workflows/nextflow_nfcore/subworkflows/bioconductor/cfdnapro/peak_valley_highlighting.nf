#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cfdnapro — peak_valley_highlighting
// Identify and visually highlight specific peak and valley locations on a single sample's fragmentation pattern.
// Input: exam_path
// Container: quay.io/biocontainers/bioconductor-cfdnapro:1.16.1--r45hdfd78af_0
// R packages: cfDNAPro, dplyr, ggplot2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CFDNAPRO_PEAK_VALLEY_HIGHLIGHTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cfdnapro:1.16.1--r45hdfd78af_0"

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
    library(ggplot2)
    library(dplyr)
    
    # Define the input path from the working directory
    exam_path <- "exam_path"
    
    # Validate that the input directory exists
    if (!dir.exists(exam_path)) {
      stop(paste("Error: The input directory '", exam_path, "' does not exist in the working directory. Please ensure it is present and contains the cohort sub-folders with Picard txt or BAM files.", sep = ""))
    }
    
    # --- Calculate peak distances ---
    peaks <- callPeakDistance(path = exam_path) 
    
    # --- Calculate valley distances ---
    valleys <- callValleyDistance(path = exam_path) 
    
    # --- Generate the base fragmentation pattern plot ---
    exam_plot_all <- callSize(path=exam_path) %>% plotSingleGroup(vline = NULL)
    
    # --- Overlay peak and valley locations as vertical lines ---
    exam_plot_prop <- exam_plot_all\$prop + 
      coord_cartesian(xlim = c(90,135),ylim = c(0,0.0065)) +
      geom_vline(xintercept=peaks\$insert_size, colour="red",linetype="dashed") +
      geom_vline(xintercept = valleys\$insert_size,colour="blue")
    
    # --- Overlay peak and valley locations as dots ---
    exam_plot_prop_dot<- exam_plot_all\$prop + 
      coord_cartesian(xlim = c(90,135),ylim = c(0,0.0065)) +
      geom_point(data= peaks, 
                 mapping = aes(x= insert_size, y= prop),
                 color="blue",alpha=0.5,size=3) +
      geom_point(data= valleys, 
                 mapping = aes(x= insert_size, y= prop),
                 color="red",alpha=0.5,size=3)
    
    # Save meaningful results to the working directory
    write.csv(peaks, "peaks.csv", row.names = FALSE)
    write.csv(valleys, "valleys.csv", row.names = FALSE)
    
    ggsave("exam_plot_prop.pdf", plot = exam_plot_prop, width = 8, height = 6)
    ggsave("exam_plot_prop_dot.pdf", plot = exam_plot_prop_dot, width = 8, height = 6)

    writeLines(c(
        '"BIOC_CFDNAPRO_PEAK_VALLEY_HIGHLIGHTING":',
        paste0('        cfdnapro: ', as.character(packageVersion("cfdnapro")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peak_valley_highlighting.csv versions.yml
    """
}

workflow BIOC_CFDNAPRO_PEAK_VALLEY_HIGHLIGHTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exam_path ] ]

    main:
    BIOC_CFDNAPRO_PEAK_VALLEY_HIGHLIGHTING(ch_input)

    emit:
    tables   = BIOC_CFDNAPRO_PEAK_VALLEY_HIGHLIGHTING.out.tables
    plots    = BIOC_CFDNAPRO_PEAK_VALLEY_HIGHLIGHTING.out.plots
    objects  = BIOC_CFDNAPRO_PEAK_VALLEY_HIGHLIGHTING.out.objects
    versions = BIOC_CFDNAPRO_PEAK_VALLEY_HIGHLIGHTING.out.versions
}
