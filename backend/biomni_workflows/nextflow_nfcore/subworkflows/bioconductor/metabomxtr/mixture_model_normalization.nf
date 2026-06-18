#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metabomxtr — mixture_model_normalization
// Normalize batch and technical effects in experimental metabolomics data using repeated control/QC samples while accounting for batch-specific thresholds of dete
// Input: experimental_samples.csv, control_samples.csv
// Container: quay.io/biocontainers/bioconductor-metabomxtr:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, metabomxtr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read user input files from the working directory
//  * 2. [Input & Preparation] Run mixture model normalization using mixnorm, specifying
//  * 3. [Input & Preparation] Assess normalization performance and identify outliers
//  * 4. [Input & Preparation] Run normalization preserving biological covariates (e.g.,

nextflow.enable.dsl = 2

process BIOC_METABOMXTR_MIXTURE_MODEL_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("metabomxtr", "ggplot2")
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
        library(metabomxtr)
        library(ggplot2)
        
        # --- Read user input files from the working directory ---
        # - experimental_samples.csv: raw experimental metabolite abundances and batch/phenotype covariates
        # - control_samples.csv: raw quality control pool metabolite abundances, batch, and run order/phenotype covariates
        euMetabData <- read.csv("experimental_samples.csv", row.names = 1, check.names = FALSE)
        euMetabCData <- read.csv("control_samples.csv", row.names = 1, check.names = FALSE)
        
        # Dynamically identify metabolite names (numeric columns present in both, excluding 'batch')
        num_cols_data <- names(euMetabData)[sapply(euMetabData, is.numeric)]
        num_cols_cdata <- names(euMetabCData)[sapply(euMetabCData, is.numeric)]
        ynames <- setdiff(intersect(num_cols_data, num_cols_cdata), "batch")
        
        # Dynamically identify covariates (columns present in both, excluding 'batch' and metabolites)
        common_cols <- intersect(names(euMetabData), names(euMetabCData))
        covariates <- setdiff(common_cols, c("batch", ynames))
        
        # Construct mixture model formula dynamically
        if (length(covariates) > 0) {
          model_terms <- paste(c(covariates, "batch"), collapse = "+")
          mxtr_formula <- as.formula(paste("~", model_terms, "|", model_terms))
        } else {
          mxtr_formula <- ~batch|batch
        }
        
        # --- Run mixture model normalization using mixnorm, specifying ---
        euMetabNorm <- mixnorm(ynames, batch="batch", mxtrModel=mxtr_formula, 
                               cData=euMetabCData, data=euMetabData, qc.sd.outliers=2)
        
        # Save results of the standard mixture model normalization
        write.csv(euMetabNorm\$obsNorm, "normalized_experimental_samples.csv", row.names = TRUE)
        write.csv(euMetabNorm\$ctlNorm, "normalized_control_samples.csv", row.names = TRUE)
        write.csv(euMetabNorm\$normParamsZ, "normalization_parameters.csv", row.names = TRUE)
        write.csv(euMetabNorm\$conv, "normalization_convergence.csv", row.names = FALSE)
        saveRDS(euMetabNorm, "euMetabNorm.rds")
        
        # Start PDF device to capture diagnostic plots
        pdf("normalization_plots.pdf", width = 11, height = 8.5)
        
        # --- Assess normalization performance and identify outliers ---
        if (length(covariates) > 0) {
          plot.list <- lapply(ynames, metabplot, batch="batch", raw.obs.data=euMetabData, raw.cont.data=euMetabCData, 
                              norm.obs.data=euMetabNorm\$obsNorm, norm.cont.data=euMetabNorm\$ctlNorm,
                              color.var=covariates[1], cont.outlier.sd.thresh=2, norm.outlier.sd.thresh=4)
        } else {
          plot.list <- lapply(ynames, metabplot, batch="batch", raw.obs.data=euMetabData, raw.cont.data=euMetabCData, 
                              norm.obs.data=euMetabNorm\$obsNorm, norm.cont.data=euMetabNorm\$ctlNorm,
                              cont.outlier.sd.thresh=2, norm.outlier.sd.thresh=4)
        }
        
        # Print the generated diagnostic plots to the PDF
        for (p in plot.list) {
          print(p)
        }
        
        # --- Run normalization preserving biological covariates (e.g., ---
        if (length(covariates) > 0) {
          euMetabNormRC <- mixnorm(ynames, batch="batch", mxtrModel=mxtr_formula, 
                                   cData=euMetabCData, removeCorrection=covariates, data=euMetabData)
        } else {
          euMetabNormRC <- mixnorm(ynames, batch="batch", mxtrModel=mxtr_formula, 
                                   cData=euMetabCData, data=euMetabData)
        }
        
        # Save results of the normalization with preserved biological covariates
        write.csv(euMetabNormRC\$obsNorm, "normalized_experimental_samples_RC.csv", row.names = TRUE)
        write.csv(euMetabNormRC\$ctlNorm, "normalized_control_samples_RC.csv", row.names = TRUE)
        write.csv(euMetabNormRC\$normParamsZ, "normalization_parameters_RC.csv", row.names = TRUE)
        write.csv(euMetabNormRC\$conv, "normalization_convergence_RC.csv", row.names = FALSE)
        saveRDS(euMetabNormRC, "euMetabNormRC.rds")
        
        # Generate and print diagnostic plot for the preserved-covariate normalization
        if (length(covariates) > 0) {
          p_rc <- metabplot(ynames[1], batch="batch", raw.obs.data=euMetabData, raw.cont.data=euMetabCData, 
                            norm.obs.data=euMetabNormRC\$obsNorm, norm.cont.data=euMetabNormRC\$ctlNorm, 
                            color.var=covariates[1], cont.outlier.sd.thresh=2, norm.outlier.sd.thresh=4)
        } else {
          p_rc <- metabplot(ynames[1], batch="batch", raw.obs.data=euMetabData, raw.cont.data=euMetabCData, 
                            norm.obs.data=euMetabNormRC\$obsNorm, norm.cont.data=euMetabNormRC\$ctlNorm, 
                            cont.outlier.sd.thresh=2, norm.outlier.sd.thresh=4)
        }
        print(p_rc)
        
        # Close the PDF device
        dev.off()

    writeLines(c(
        '"BIOC_METABOMXTR_MIXTURE_MODEL_NORMALIZATION":',
        paste0('    metabomxtr: ', as.character(packageVersion('metabomxtr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mixture_model_normalization.csv versions.yml
    """
}

workflow BIOC_METABOMXTR_MIXTURE_MODEL_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ experimental_samples.csv, control_samples.csv ] ]

    main:
    BIOC_METABOMXTR_MIXTURE_MODEL_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_METABOMXTR_MIXTURE_MODEL_NORMALIZATION.out.tables
    plots    = BIOC_METABOMXTR_MIXTURE_MODEL_NORMALIZATION.out.plots
    objects  = BIOC_METABOMXTR_MIXTURE_MODEL_NORMALIZATION.out.objects
    versions = BIOC_METABOMXTR_MIXTURE_MODEL_NORMALIZATION.out.versions
}
