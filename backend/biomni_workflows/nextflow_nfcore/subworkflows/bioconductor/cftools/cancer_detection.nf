#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cfTools — cancer_detection
// Detect tumor-derived cfDNA fragments, estimate tumor burden, and visualize the resulting fractions.
// Input: CancerDetector.reads.txt.gz, CancerDetector.markers.txt.gz
// Container: quay.io/biocontainers/bioconductor-cftools:1.10.0--r45ha27e39d_0
// R packages: cfTools
// Bioconductor: 3.20 | R: 4.4
// Requires: cfTools
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run CancerDetector to estimate tumor burden and normal cfDNA fraction
//  * 2. [Visualization & Output] Visualize the estimated fractions using PlotFractionPie

nextflow.enable.dsl = 2

process BIOC_CFTOOLS_CANCER_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("cfTools")
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
    library(cfTools)
    
    # Define input files in the working directory
    fragMethFile <- "CancerDetector.reads.txt.gz"
    markerParamFile <- "CancerDetector.markers.txt.gz"
    
    # Verify input files exist
    if (!file.exists(fragMethFile)) {
      stop(paste("Required input file missing in working directory:", fragMethFile))
    }
    if (!file.exists(markerParamFile)) {
      stop(paste("Required input file missing in working directory:", markerParamFile))
    }
    
    # Display the first few rows of the input files as shown in the documentation
    message("Displaying first few rows of fragment-level methylation states:")
    print(head(read.csv(fragMethFile, sep = "\t", colClasses = "character"), 4))
    
    message("Displaying first few rows of marker parameters:")
    print(head(read.csv(markerParamFile, sep = "\t"), 4))
    
    # Run CancerDetector to estimate tumor burden and normal cfDNA fraction
    message("Running CancerDetector...")
    cancer_normal_df <- CancerDetector(fragMethFile, markerParamFile, lambda=0.5, id="test")
    
    # Print the results
    message("CancerDetector Results:")
    print(cancer_normal_df)
    
    # Write the results to a CSV file
    output_csv <- "cancer_detection_results.csv"
    write.csv(cancer_normal_df, file = output_csv, row.names = FALSE)
    message(paste("Results saved to:", output_csv))
    
    # Save the visualization to a PDF file
    output_pdf <- "cfDNA_composition_pie.pdf"
    pdf(file = output_pdf, width = 6, height = 6)
    PlotFractionPie(cancer_normal_df, title = "cfDNA Composition", class_colors = c("normal_cfDNA_fraction" = "blue"), font_size = 1.2)
    dev.off()
    message(paste("Pie chart saved to:", output_pdf))

    writeLines(c(
        '"BIOC_CFTOOLS_CANCER_DETECTION":',
        paste0('    cfTools: ', as.character(packageVersion('cfTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cancer_detection.csv versions.yml
    """
}

workflow BIOC_CFTOOLS_CANCER_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CancerDetector.reads.txt.gz, CancerDetector.markers.txt.gz ] ]

    main:
    BIOC_CFTOOLS_CANCER_DETECTION(ch_input)

    emit:
    tables   = BIOC_CFTOOLS_CANCER_DETECTION.out.tables
    plots    = BIOC_CFTOOLS_CANCER_DETECTION.out.plots
    objects  = BIOC_CFTOOLS_CANCER_DETECTION.out.objects
    versions = BIOC_CFTOOLS_CANCER_DETECTION.out.versions
}
