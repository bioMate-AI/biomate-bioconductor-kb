#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cfdnapro — peak_valley_highlighting
// Identify and visually highlight specific peak and valley locations on a single sample's fragmentation pattern.
// Input: exam_path
// Container: quay.io/biocontainers/bioconductor-cfdnapro:1.16.1--r45hdfd78af_0
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
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
    
    # 1. Calculate peak distances
    peaks <- callPeakDistance(path = exam_path) 
    
    # 2. Calculate valley distances
    valleys <- callValleyDistance(path = exam_path) 
    
    # 3. Generate the base fragmentation pattern plot
    exam_plot_all <- callSize(path=exam_path) %>% plotSingleGroup(vline = NULL)
    
    # 4. Overlay peak and valley locations as vertical lines
    exam_plot_prop <- exam_plot_all\$prop + 
      coord_cartesian(xlim = c(90,135),ylim = c(0,0.0065)) +
      geom_vline(xintercept=peaks\$insert_size, colour="red",linetype="dashed") +
      geom_vline(xintercept = valleys\$insert_size,colour="blue")
    
    # 5. Overlay peak and valley locations as dots
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

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CFDNAPRO_PEAK_VALLEY_HIGHLIGHTING":
        cfdnapro: \$(Rscript -e 'cat(as.character(packageVersion("cfdnapro")))')
    END_VERSIONS
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
