#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: randRotation — contrast_analysis_batch_correction
// Test specific contrasts in batch-corrected data using random rotations to obtain unskewed p-values.
// Input: edata, pdata
// Container: quay.io/biocontainers/bioconductor-randrotation:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: limma, randRotation, sva
// Visualizations: plot (ggplot/base)
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create the model matrix and define the contrast matrix
//  * 2. [Input & Preparation] Transform the model matrix to include the contrast as the
//  * 3. [Input & Preparation] Initialize the batch random rotation object using
//  * 4. [Input & Preparation] Define a custom statistic function that performs batch
//  * 5. [Input & Preparation] Run the rotation using rotateStat and calculate p-values

nextflow.enable.dsl = 2

process BIOC_RANDROTATION_CONTRAST_ANALYSIS_BATCH_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("randRotation", "limma", "sva")
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
    library(randRotation)
    library(limma)
    library(sva)
    
    # Helper function to robustly find and read input files
    find_and_read <- function(base_name) {
      extensions <- c(".csv", ".tsv", ".txt", ".rds")
      for (ext in extensions) {
        file_name <- paste0(base_name, ext)
        if (file.exists(file_name)) {
          if (ext == ".rds") {
            return(readRDS(file_name))
          } else if (ext == ".csv") {
            return(read.csv(file_name, row.names = 1, check.names = FALSE))
          } else {
            return(read.delim(file_name, row.names = 1, check.names = FALSE))
          }
        }
      }
      if (file.exists(base_name)) {
        tryCatch({
          return(readRDS(base_name))
        }, error = function(e) {
          return(read.csv(base_name, row.names = 1, check.names = FALSE))
        })
      }
      stop(paste("Required file", base_name, "not found in the working directory."))
    }
    
    # Read user input files
    edata <- as.matrix(find_and_read("edata"))
    pdata <- find_and_read("pdata")
    
    # Ensure batch is properly formatted as a factor
    if (!"batch" %in% colnames(pdata)) {
      stop("pdata must contain a 'batch' column.")
    }
    pdata\$batch <- as.factor(pdata\$batch)
    
    # Identify the group/condition column dynamically
    if ("group" %in% colnames(pdata)) {
      group_col <- "group"
    } else {
      group_col <- setdiff(colnames(pdata), "batch")[1]
    }
    if (is.na(group_col)) {
      stop("pdata must contain at least one condition column besides 'batch'.")
    }
    group <- as.factor(pdata[[group_col]])
    
    # --- Create the model matrix and define the contrast matrix ---
    mod.groups <- model.matrix(~ group)
    # Ensure column names are valid R variable names to prevent makeContrasts from failing on spaces/special characters
    colnames(mod.groups) <- make.names(colnames(mod.groups))
    
    coef_names <- colnames(mod.groups)
    if (length(coef_names) < 2) {
      stop("The condition factor must have at least two levels.")
    }
    
    # Dynamically define the contrast for the first non-intercept coefficient
    target_coef <- coef_names[2]
    contrasts1 <- limma::makeContrasts(contrasts = target_coef, levels = mod.groups)
    
    # --- Transform the model matrix to include the contrast as the ---
    mod.cont <- contrastModel(X = mod.groups, C = contrasts1)
    
    # --- Initialize the batch random rotation object using ---
    init1 <- initBatchRandrot(edata, mod.cont, batch = pdata\$batch)
    
    # --- Define a custom statistic function that performs batch ---
    statistic <- function(Y, batch, mod, cont){
      Y.tmp <- sva::ComBat(dat = Y, batch = batch, mod = mod)
      fit1 <- limma::lmFit(Y.tmp, mod)
      fit1 <- limma::contrasts.fit(fit1, cont)
      fit1 <- limma::eBayes(fit1)
      abs(fit1\$t[,1])
    }
    
    # --- Run the rotation using rotateStat and calculate p-values ---
    res1 <- rotateStat(initialised.obj = init1, R = 20, statistic = statistic,
                       batch = pdata\$batch, mod = mod.groups, cont = contrasts1)
    p.rot <- pFdr(res1)
    
    # Write outputs
    write.csv(data.frame(p_value = p.rot), "p_values_rotated.csv", row.names = TRUE)
    saveRDS(res1, "rotate_stat_results.rds")
    
    # Generate and save diagnostic plot
    pdf("p_values_histogram.pdf")
    main_title <- paste("Rotation-based p-values (", target_coef, ")", sep="")
    hist(p.rot, freq = FALSE, col = "lightgreen", breaks = seq(0, 1, 0.1),
         main = main_title, xlab = "p-value")
    abline(h = 1, col = "blue", lty = 2)
    dev.off()

    writeLines(c(
        '"BIOC_RANDROTATION_CONTRAST_ANALYSIS_BATCH_CORRECTION":',
        paste0('    randRotation: ', as.character(packageVersion('randRotation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_contrast_analysis_batch_correction.csv versions.yml
    """
}

workflow BIOC_RANDROTATION_CONTRAST_ANALYSIS_BATCH_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ edata, pdata ] ]

    main:
    BIOC_RANDROTATION_CONTRAST_ANALYSIS_BATCH_CORRECTION(ch_input)

    emit:
    tables   = BIOC_RANDROTATION_CONTRAST_ANALYSIS_BATCH_CORRECTION.out.tables
    plots    = BIOC_RANDROTATION_CONTRAST_ANALYSIS_BATCH_CORRECTION.out.plots
    objects  = BIOC_RANDROTATION_CONTRAST_ANALYSIS_BATCH_CORRECTION.out.objects
    versions = BIOC_RANDROTATION_CONTRAST_ANALYSIS_BATCH_CORRECTION.out.versions
}
