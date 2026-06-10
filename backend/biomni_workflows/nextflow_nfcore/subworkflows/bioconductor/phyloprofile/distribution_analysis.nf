#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PhyloProfile — distribution_analysis
// Plot the distribution of values for the integrated annotation layers to help decide on filtering thresholds.
// Input: raw_profile.txt
// Container: quay.io/biocontainers/bioconductor-phyloprofile:2.2.2--r45hdfd78af_0
// R packages: PhyloProfile, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: PhyloProfile, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Process data for distribution analysis using `createVariableDistributionData`
//  * 2. [Visualization & Output] Define plotting parameters
//  * 3. [Visualization & Output] Generate distribution plot using `createVarDistPlot`

nextflow.enable.dsl = 2

process BIOC_PHYLOPROFILE_DISTRIBUTION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("PhyloProfile", "ggplot2")
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
    library(PhyloProfile)
    library(ggplot2)
    
    # 1. Read user input
    # Read the raw phylogenetic profile data from the working directory
    mainLongRaw <- read.table("raw_profile.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # 2. Process data for distribution analysis
    data <- createVariableDistributionData(
        mainLongRaw, c(0, 1), c(0.5, 1)
    )
    
    # Save the processed distribution data to a CSV file
    write.csv(data, "processed_distribution_data.csv", row.names = FALSE)
    
    # 3. Define plotting parameters
    varType <- "var1"
    varName <- "Variable 1"
    percentCutoff <- c(0,1)
    distTextSize <- 12
    
    # 4. Generate distribution plot
    p <- createVarDistPlot(
        data,
        varName,
        varType,
        percentCutoff,
        distTextSize
    )
    
    # Save the generated plot to a PDF file
    ggsave("distribution_plot.pdf", plot = p, width = 8, height = 6)

    writeLines(c(
        '"BIOC_PHYLOPROFILE_DISTRIBUTION_ANALYSIS":',
        paste0('    PhyloProfile: ', as.character(packageVersion('PhyloProfile')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_distribution_analysis.csv versions.yml
    """
}

workflow BIOC_PHYLOPROFILE_DISTRIBUTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_profile.txt ] ]

    main:
    BIOC_PHYLOPROFILE_DISTRIBUTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PHYLOPROFILE_DISTRIBUTION_ANALYSIS.out.tables
    plots    = BIOC_PHYLOPROFILE_DISTRIBUTION_ANALYSIS.out.plots
    objects  = BIOC_PHYLOPROFILE_DISTRIBUTION_ANALYSIS.out.objects
    versions = BIOC_PHYLOPROFILE_DISTRIBUTION_ANALYSIS.out.versions
}
