#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cfdnapro — single_cohort_analysis
// Characterize and visualize fragment size distribution (proportions and cumulative distribution functions) for a single cohort.
// Input: data_path
// Container: quay.io/biocontainers/bioconductor-cfdnapro:1.16.1--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CFDNAPRO_SINGLE_COHORT_ANALYSIS {
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
    .bm_deps <- c("cfdnapro", "dplyr", "ggplot2", "ggpubr", "scales")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(cfDNAPro)
    library(dplyr)
    library(ggplot2)
    
    # Stage 1: Retrieve the path to the input data directory
    # (Adapted from the documented cfDNAPro::examplePath("groups_picard") to read the user-provided directory)
    data_path <- "data_path"
    
    # Verify that the input directory exists and contains sub-folders
    if (!dir.exists(data_path)) {
      stop(paste("Error: Input directory 'data_path' does not exist at:", normalizePath(data_path, mustWork = FALSE)))
    }
    
    # Stage 2, 3, & 4: Extract fragment size distribution data, filter for the target cohort,
    # and generate proportion and cumulative distribution plots.
    # Keeping the exact documented function calls and arguments.
    cohort1_plot <- cfDNAPro::callSize(path = data_path) %>%
      dplyr::filter(group == as.character("cohort_1")) %>%
      cfDNAPro::plotSingleGroup()
    
    # Save the resulting list of ggplot2 objects as an RDS file
    saveRDS(cohort1_plot, file = "cohort1_plot.rds")
    
    # Save the generated plots (prop_plot, cdf_plot, etc.) to a PDF file
    pdf("cohort1_fragment_size_plots.pdf", width = 10, height = 7)
    for (plot_name in names(cohort1_plot)) {
      tryCatch({
        print(cohort1_plot[[plot_name]])
      }, error = function(e) {
        warning(paste("Could not print plot:", plot_name, "-", e\$message))
      })
    }
    invisible(dev.off())
    
    message("Pipeline completed successfully. Outputs saved to 'cohort1_plot.rds' and 'cohort1_fragment_size_plots.pdf'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CFDNAPRO_SINGLE_COHORT_ANALYSIS":
        cfdnapro: \$(Rscript -e 'cat(as.character(packageVersion("cfdnapro")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cohort_analysis.csv versions.yml
    """
}

workflow BIOC_CFDNAPRO_SINGLE_COHORT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data_path ] ]

    main:
    BIOC_CFDNAPRO_SINGLE_COHORT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CFDNAPRO_SINGLE_COHORT_ANALYSIS.out.tables
    plots    = BIOC_CFDNAPRO_SINGLE_COHORT_ANALYSIS.out.plots
    objects  = BIOC_CFDNAPRO_SINGLE_COHORT_ANALYSIS.out.objects
    versions = BIOC_CFDNAPRO_SINGLE_COHORT_ANALYSIS.out.versions
}
