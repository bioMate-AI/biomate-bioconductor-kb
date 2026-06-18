#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: quantiseqr — deconvolution_from_summarized_experiment
// Perform immune cell deconvolution on a SummarizedExperiment object, appending the results to the colData slot, and extract the quantifications.
// Input: summarized_experiment.rds
// Container: quay.io/biocontainers/bioconductor-quantiseqr:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, dplyr, ggplot2, quantiseqr, tibble, tidyr
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the deconvolution using run_quantiseq
//  * 2. [Visualization & Output] Extract the TIL10-relevant quantifications from the updated SummarizedExperiment using extract_ti_from_se

nextflow.enable.dsl = 2

process BIOC_QUANTISEQR_DECONVOLUTION_FROM_SUMMARIZED_EXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("quantiseqr", "SummarizedExperiment", "ggplot2", "tidyr", "dplyr", "tibble")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library("quantiseqr")
    library("SummarizedExperiment")
    library("ggplot2")
    library("tidyr")
    library("dplyr")
    library("tibble")
    
    # 1. Read the user input file
    # The pipeline expects "summarized_experiment.rds" in the working directory
    input_file <- "summarized_experiment.rds"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    se_Song2017_MAPKi_treatment <- readRDS(input_file)
    
    # 2. Run the deconvolution using run_quantiseq
    # Keeping function call and argument names EXACTLY as documented
    se_Song2017_MAPKi_treatment_tiquant <- quantiseqr::run_quantiseq(
      expression_data = se_Song2017_MAPKi_treatment,
      signature_matrix = "TIL10",
      is_arraydata = FALSE,
      is_tumordata = TRUE,
      scale_mRNA = TRUE
    )
    
    # 3. Extract the TIL10-relevant quantifications from the updated SummarizedExperiment
    ti_quant <- quantiseqr::extract_ti_from_se(se_Song2017_MAPKi_treatment_tiquant)
    
    # 4. Write output files
    # Save the updated SummarizedExperiment object containing deconvolution results in colData
    saveRDS(se_Song2017_MAPKi_treatment_tiquant, "deconvoluted_summarized_experiment.rds")
    
    # Save the extracted cell fractions as a CSV table
    write.csv(as.data.frame(ti_quant), "extracted_cell_fractions.csv", row.names = TRUE)
    
    # Generate and save a stacked barplot of the cell fractions
    pdf("cell_fractions_barplot.pdf", width = 10, height = 7)
    tryCatch({
      # Attempt to plot using the compact wrapper on the SummarizedExperiment
      print(quantiseqr::quantiplot(se_Song2017_MAPKi_treatment_tiquant))
    }, error = function(e) {
      # Fallback to plotting the extracted cell fractions
      print(quantiseqr::quantiplot(ti_quant))
    })
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'deconvoluted_summarized_experiment.rds', 'extracted_cell_fractions.csv', and 'cell_fractions_barplot.pdf'.")

    writeLines(c(
        '"BIOC_QUANTISEQR_DECONVOLUTION_FROM_SUMMARIZED_EXPERIMENT":',
        paste0('    quantiseqr: ', as.character(packageVersion('quantiseqr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deconvolution_from_summarized_experiment.csv versions.yml
    """
}

workflow BIOC_QUANTISEQR_DECONVOLUTION_FROM_SUMMARIZED_EXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ summarized_experiment.rds ] ]

    main:
    BIOC_QUANTISEQR_DECONVOLUTION_FROM_SUMMARIZED_EXPERIMENT(ch_input)

    emit:
    tables   = BIOC_QUANTISEQR_DECONVOLUTION_FROM_SUMMARIZED_EXPERIMENT.out.tables
    plots    = BIOC_QUANTISEQR_DECONVOLUTION_FROM_SUMMARIZED_EXPERIMENT.out.plots
    objects  = BIOC_QUANTISEQR_DECONVOLUTION_FROM_SUMMARIZED_EXPERIMENT.out.objects
    versions = BIOC_QUANTISEQR_DECONVOLUTION_FROM_SUMMARIZED_EXPERIMENT.out.versions
}
