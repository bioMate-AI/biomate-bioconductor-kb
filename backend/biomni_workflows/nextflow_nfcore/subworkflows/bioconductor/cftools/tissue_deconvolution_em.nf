#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cfTools — tissue_deconvolution_em
// Estimate fractions of cfDNA fragments from different tissues using an EM algorithm.
// Input: cfDeconvolve.reads.txt.gz, cfDeconvolve.markers.txt.gz
// Container: quay.io/biocontainers/bioconductor-cftools:1.10.0--r45ha27e39d_0
// R packages: cfTools
// Bioconductor: 3.20 | R: 4.4
// Requires: cfTools
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define EM algorithm parameters
//  * 2. [Core Analysis] Run cfDeconvolve to estimate tissue fractions and unknown class fraction

nextflow.enable.dsl = 2

process BIOC_CFTOOLS_TISSUE_DECONVOLUTION_EM {
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
        
        # Define input file paths in the working directory
        fragMethFile2 <- "cfDeconvolve.reads.txt.gz"
        markerParamFile2 <- "cfDeconvolve.markers.txt.gz"
        
        # Verify that the input files exist
        if (!file.exists(fragMethFile2)) {
          stop(paste("Required input file missing:", fragMethFile2))
        }
        if (!file.exists(markerParamFile2)) {
          stop(paste("Required input file missing:", markerParamFile2))
        }
        
        # Preview the input files (as shown in the documented code)
        message("Previewing fragment-level methylation states:")
        print(head(read.csv(fragMethFile2, header=TRUE, sep="\t", 
                            colClasses = "character"), 4))
        
        message("Previewing marker parameters:")
        marker_data <- read.csv(markerParamFile2, header=TRUE, sep="\t", 
                                colClasses = "character")
        print(head(marker_data, 4))
        
        # Stage 1: Define EM algorithm parameters
        numTissues <- ncol(marker_data) - 1
        emAlgorithmType <- "em.global.unknown"
        likelihoodRatioThreshold <- 2
        emMaxIterations <- 100
        randomSeed <- 0
        id <- "test"
        
        # Stage 2: Run cfDeconvolve to estimate tissue fractions and unknown class fraction
        message("Running cfDeconvolve...")
        tissueFraction <- cfDeconvolve(fragMethFile2, markerParamFile2, numTissues, 
                                       emAlgorithmType, likelihoodRatioThreshold, 
                                       emMaxIterations, randomSeed, id)
        
        # Print the estimated tissue fractions
        message("Estimated tissue fractions:")
        print(tissueFraction)
        
        # Save the results to output files
        message("Saving results...")
        write.csv(tissueFraction, file = "tissue_deconvolution_results.csv", row.names = FALSE)
        saveRDS(tissueFraction, file = "tissue_deconvolution_results.rds")
        
        # Generate and save a pie chart visualization of the fractions
        pdf("tissue_deconvolution_pie_chart.pdf", width = 8, height = 8)
        tryCatch({
          # Attempt to plot using the tissueFraction data frame directly
          print(PlotFractionPie(tissueFraction, title = "cfDNA Tissue Composition", font_size = 1.2))
        }, error = function(e) {
          message("Direct plotting failed, attempting with vector conversion...")
          tryCatch({
            # Fallback: convert the first row to a named numeric vector
            fraction_vector <- as.numeric(tissueFraction[1, ])
            names(fraction_vector) <- colnames(tissueFraction)
            print(PlotFractionPie(fraction_vector, title = "cfDNA Tissue Composition", font_size = 1.2))
          }, error = function(e2) {
            warning("Could not generate pie chart: ", e2\$message)
          })
        })
        dev.off()
        
        message("Pipeline completed successfully. Outputs written to:")
        message("- tissue_deconvolution_results.csv")
        message("- tissue_deconvolution_results.rds")
        message("- tissue_deconvolution_pie_chart.pdf")

    writeLines(c(
        '"BIOC_CFTOOLS_TISSUE_DECONVOLUTION_EM":',
        paste0('    cfTools: ', as.character(packageVersion('cfTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tissue_deconvolution_em.csv versions.yml
    """
}

workflow BIOC_CFTOOLS_TISSUE_DECONVOLUTION_EM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cfDeconvolve.reads.txt.gz, cfDeconvolve.markers.txt.gz ] ]

    main:
    BIOC_CFTOOLS_TISSUE_DECONVOLUTION_EM(ch_input)

    emit:
    tables   = BIOC_CFTOOLS_TISSUE_DECONVOLUTION_EM.out.tables
    plots    = BIOC_CFTOOLS_TISSUE_DECONVOLUTION_EM.out.plots
    objects  = BIOC_CFTOOLS_TISSUE_DECONVOLUTION_EM.out.objects
    versions = BIOC_CFTOOLS_TISSUE_DECONVOLUTION_EM.out.versions
}
