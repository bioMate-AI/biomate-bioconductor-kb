#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: signeR — exposure_estimation_to_known_signatures
// Estimate sample exposures to a set of predefined, known mutational signatures (e.g., COSMIC signatures) while keeping the signatures fixed.
// Input: 21_breast_cancers.mutations.txt, 21_breast_cancers.opportunity.txt, Cosmic_signatures_BRC.txt
// Container: quay.io/biocontainers/bioconductor-signer:2.12.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: signeR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read mutation counts and opportunity matrices from files
//  * 2. [Input & Preparation] Read known signatures matrix
//  * 3. [Core Analysis] Run signeR with fixedP=TRUE to estimate exposures to known signatures
//  * 4. [Core Analysis] Extract median exposures using Median_exp

nextflow.enable.dsl = 2

process BIOC_SIGNER_EXPOSURE_ESTIMATION_TO_KNOWN_SIGNATURES {
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
    .bm_deps <- c("signeR")
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
    library(signeR)
    
    # 1. Read mutation counts and opportunity matrices from local files
    mut <- read.table("21_breast_cancers.mutations.txt", header=TRUE, check.names=FALSE)
    opp <- read.table("21_breast_cancers.opportunity.txt")
    
    # 2. Read known signatures matrix from local file
    Pmatrix <- as.matrix(read.table("Cosmic_signatures_BRC.txt", sep="\t", check.names=FALSE))
    
    # 3. Run signeR with fixedP=TRUE to estimate exposures to known signatures
    exposures.known.sigs <- signeR(M=mut, Opport=opp, P=Pmatrix, fixedP=TRUE, main_eval=100, EM_eval=50, EMit_lim=20)
    
    # 4. Extract median exposures using Median_exp
    exposures <- Median_exp(exposures.known.sigs\$SignExposures)
    
    # 5. Save meaningful results to output files
    # Save the median exposures as a CSV table
    write.csv(exposures, file="exposures_median.csv", row.names=TRUE)
    
    # Save the complete signeR output object as an RDS file
    saveRDS(exposures.known.sigs, file="exposures_known_sigs.rds")
    
    # Generate and save diagnostic and exposure plots to a PDF
    pdf("exposure_analysis_plots.pdf", width=10, height=7)
    
    # Plot MCMC paths for the parameters
    tryCatch({
      Paths(exposures.known.sigs\$SignExposures)
    }, error=function(e) {
      message("Could not generate MCMC paths plot: ", e\$message)
    })
    
    # Plot exposure boxplot
    tryCatch({
      ExposureBoxplot(exposures.known.sigs\$SignExposures)
    }, error=function(e) {
      message("Could not generate ExposureBoxplot: ", e\$message)
    })
    
    # Plot exposure barplot
    tryCatch({
      ExposureBarplot(exposures.known.sigs\$SignExposures)
    }, error=function(e) {
      message("Could not generate ExposureBarplot: ", e\$message)
    })
    
    # Plot relative exposure barplot
    tryCatch({
      ExposureBarplot(exposures.known.sigs\$SignExposures, relative=TRUE)
    }, error=function(e) {
      message("Could not generate relative ExposureBarplot: ", e\$message)
    })
    
    # Plot exposure heatmap
    tryCatch({
      ExposureHeat(exposures.known.sigs\$SignExposures)
    }, error=function(e) {
      message("Could not generate ExposureHeat: ", e\$message)
    })
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'exposures_median.csv', 'exposures_known_sigs.rds', and 'exposure_analysis_plots.pdf'.")

    writeLines(c(
        '"BIOC_SIGNER_EXPOSURE_ESTIMATION_TO_KNOWN_SIGNATURES":',
        paste0('    signeR: ', as.character(packageVersion('signeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_exposure_estimation_to_known_signatures.csv versions.yml
    """
}

workflow BIOC_SIGNER_EXPOSURE_ESTIMATION_TO_KNOWN_SIGNATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ 21_breast_cancers.mutations.txt, 21_breast_cancers.opportunity.txt, Cosmic_signatures_BRC.txt ] ]

    main:
    BIOC_SIGNER_EXPOSURE_ESTIMATION_TO_KNOWN_SIGNATURES(ch_input)

    emit:
    tables   = BIOC_SIGNER_EXPOSURE_ESTIMATION_TO_KNOWN_SIGNATURES.out.tables
    plots    = BIOC_SIGNER_EXPOSURE_ESTIMATION_TO_KNOWN_SIGNATURES.out.plots
    objects  = BIOC_SIGNER_EXPOSURE_ESTIMATION_TO_KNOWN_SIGNATURES.out.objects
    versions = BIOC_SIGNER_EXPOSURE_ESTIMATION_TO_KNOWN_SIGNATURES.out.versions
}
