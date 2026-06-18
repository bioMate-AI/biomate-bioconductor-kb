#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HIBAG — hla_imputation_prefit
// Impute classical HLA alleles from user-provided PLINK SNP data using pre-fit published HIBAG models.
// Input: ModelList.RData, .bed, .fam, .bim
// Container: quay.io/biocontainers/bioconductor-hibag:1.46.0--r45ha27e39d_0
// R packages: ggplot2, HIBAG
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_HIBAG_HLA_IMPUTATION_PREFIT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-hibag:1.46.0--r45ha27e39d_0"

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
    .bm_deps <- c("ggplot2", "HIBAG")
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
    
    # Load the HIBAG package
    library(HIBAG)
    
    # Define the input file names as specified by the user
    model_file <- "ModelList.RData"
    bed_file <- ".bed"
    fam_file <- ".fam"
    bim_file <- ".bim"
    
    # Check for the presence of the required input files
    if (!file.exists(model_file)) {
      stop(paste("Error: Required model file", model_file, "is missing from the working directory."))
    }
    if (!file.exists(bed_file) || !file.exists(fam_file) || !file.exists(bim_file)) {
      stop("Error: One or more PLINK files (.bed, .fam, .bim) are missing from the working directory.")
    }
    
    # --- Load the pre-fit model list and extract the model for the ---
    filename <- model_file
    model.list <- get ( load (filename))
    hla.id <- "A"
    model <- hlaModelFromObj (model.list[[hla.id]])
    
    # Display model summary
    summary (model)
    
    # Save the model plot to a PDF file
    pdf("model_plot.pdf", width=8, height=6)
    plot (model)
    dev.off()
    
    # Display SNP information from the model
    head (model \$ snp.id)
    head (model \$ snp.position)
    
    # --- Import the user's PLINK BED files into HIBAG genotype ---
    yourgeno <- hlaBED2Geno ( bed.fn= ".bed" , fam.fn= ".fam" , bim.fn= ".bim" )
    summary (yourgeno)
    
    # --- Predict HLA genotypes and posterior probabilities using ---
    pred.guess <- hlaPredict (model, yourgeno, type= "response+prob" )
    summary (pred.guess)
    
    # Display prediction values and posterior probabilities in the console
    pred.guess \$ value
    pred.guess \$ postprob
    
    # Save meaningful results to output files
    saveRDS(pred.guess, file = "prediction_results.rds")
    write.csv(pred.guess\$value, file = "predicted_genotypes.csv", row.names = FALSE)
    write.csv(pred.guess\$postprob, file = "posterior_probabilities.csv", row.names = FALSE)
    
    cat("\nPipeline completed successfully. Outputs saved:\n")
    cat("- 'model_plot.pdf' (SNP frequency plot)\n")
    cat("- 'prediction_results.rds' (Complete prediction object)\n")
    cat("- 'predicted_genotypes.csv' (Best-guess HLA genotypes)\n")
    cat("- 'posterior_probabilities.csv' (Posterior probabilities for all candidates)\n")

    writeLines(c(
        '"BIOC_HIBAG_HLA_IMPUTATION_PREFIT":',
        paste0('        HIBAG: ', as.character(packageVersion("HIBAG")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hla_imputation_prefit.csv versions.yml
    """
}

workflow BIOC_HIBAG_HLA_IMPUTATION_PREFIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ModelList.RData, .bed, .fam, .bim ] ]

    main:
    BIOC_HIBAG_HLA_IMPUTATION_PREFIT(ch_input)

    emit:
    tables   = BIOC_HIBAG_HLA_IMPUTATION_PREFIT.out.tables
    plots    = BIOC_HIBAG_HLA_IMPUTATION_PREFIT.out.plots
    objects  = BIOC_HIBAG_HLA_IMPUTATION_PREFIT.out.objects
    versions = BIOC_HIBAG_HLA_IMPUTATION_PREFIT.out.versions
}
