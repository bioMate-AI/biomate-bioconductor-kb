#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: betaHMM — threshold_estimation
// Estimate methylation thresholds distinguishing hypomethylation, hemimethylation, and hypermethylation states within a single treatment condition.
// Input: pca_methylation_data[,1:5], annotation_data
// Container: quay.io/biocontainers/bioconductor-betahmm:1.6.0--r45hdfd78af_0
// R packages: betaHMM
// Bioconductor: 3.20 | R: 4.4
// Requires: betaHMM
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run threshold identification using threshold_identification
//  * 2. [Core Analysis] Extract thresholds using threshold
//  * 3. [Visualization & Output] Plot threshold results using plot

nextflow.enable.dsl = 2

process BIOC_BETAHMM_THRESHOLD_ESTIMATION {
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
    .bm_deps <- c("betaHMM")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    
    # Load required libraries
    library(betaHMM)
    
    # Helper function to read input files flexibly (CSV, TSV, or RDS)
    read_input_file <- function(base_name) {
      possible_files <- c(
        paste0(base_name, ".csv"),
        paste0(base_name, ".tsv"),
        paste0(base_name, ".txt"),
        paste0(base_name, ".rds"),
        base_name
      )
      for (f in possible_files) {
        if (file.exists(f)) {
          message(paste("Reading input file:", f))
          if (grepl("\\\\.rds\$", f, ignore.case = TRUE)) {
            return(readRDS(f))
          } else if (grepl("\\\\.(tsv|txt)\$", f, ignore.case = TRUE)) {
            return(read.delim(f, header = TRUE, stringsAsFactors = FALSE))
          } else {
            return(read.csv(f, header = TRUE, stringsAsFactors = FALSE))
          }
        }
      }
      stop(paste("Required input file not found in the working directory for:", base_name))
    }
    
    # 1. Read the declared user input files
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    pca_methylation_data <- read_input_file("pca_methylation_data")
    annotation_data <- read_input_file("annotation_data")
    
    # Ensure data frames are properly formatted
    pca_methylation_data <- as.data.frame(pca_methylation_data)
    annotation_data <- as.data.frame(annotation_data)
    
    # Define seed for reproducibility
    my.seed <- 321
    
    # 2. Run threshold identification (EXACTLY as documented)
    threshold_out <- threshold_identification(pca_methylation_data[,1:5],
                                                package_workflow = FALSE,
                                                annotation_file = annotation_data,
                                                M = 3,
                                                N = 4,
                                                parameter_estimation_only = FALSE,
                                                seed = my.seed)
    
    # 3. Extract thresholds (EXACTLY as documented)
    thresholds_extracted <- threshold(threshold_out)
    
    # Save the extracted thresholds to a CSV file
    if (is.list(thresholds_extracted)) {
      thresholds_df <- as.data.frame(thresholds_extracted)
    } else {
      thresholds_df <- data.frame(Threshold = thresholds_extracted)
    }
    write.csv(thresholds_df, "estimated_thresholds.csv", row.names = FALSE)
    
    # Save the threshold_out object as an RDS file
    saveRDS(threshold_out, "threshold_results.rds")
    
    # 4. Plot threshold results (EXACTLY as documented) and save to PDF
    pdf("threshold_fitted_density_plot.pdf", width = 7, height = 6)
    plot(threshold_out, plot_threshold = TRUE, what = "fitted density")
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved: 'estimated_thresholds.csv', 'threshold_results.rds', 'threshold_fitted_density_plot.pdf'.")

    writeLines(c(
        '"BIOC_BETAHMM_THRESHOLD_ESTIMATION":',
        paste0('    betaHMM: ', as.character(packageVersion('betaHMM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_threshold_estimation.csv versions.yml
    """
}

workflow BIOC_BETAHMM_THRESHOLD_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pca_methylation_data[,1:5], annotation_data ] ]

    main:
    BIOC_BETAHMM_THRESHOLD_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_BETAHMM_THRESHOLD_ESTIMATION.out.tables
    plots    = BIOC_BETAHMM_THRESHOLD_ESTIMATION.out.plots
    objects  = BIOC_BETAHMM_THRESHOLD_ESTIMATION.out.objects
    versions = BIOC_BETAHMM_THRESHOLD_ESTIMATION.out.versions
}
