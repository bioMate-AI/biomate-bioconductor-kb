#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: randRotation — mixed_model_batch_correction
// Perform random rotation for datasets with repeated measures (random effects) and batch structure using linear mixed models.
// Input: edata, pdata
// Container: quay.io/biocontainers/bioconductor-randrotation:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: limma, nlme, randRotation
// Visualizations: plot (ggplot/base)
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load user inputs
//  * 2. [Input & Preparation] Create the design model matrix
//  * 3. [Input & Preparation] Initialize the batch random rotation object
//  * 4. [Input & Preparation] Define the custom statistic function (exactly as
//  * 5. [Input & Preparation] Run the rotation using rotateStat and calculate p-values
//  * 6. [Input & Preparation] Write output files

nextflow.enable.dsl = 2

process BIOC_RANDROTATION_MIXED_MODEL_BATCH_CORRECTION {
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
    .bm_deps <- c("randRotation", "nlme", "limma")
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
        library(nlme)
        library(limma)
        
        # Helper function to robustly load user inputs
        load_input <- function(filename) {
          if (file.exists(filename)) {
            tryCatch({
              return(readRDS(filename))
            }, error = function(e) {
              tryCatch({
                return(read.table(filename, header = TRUE, row.names = 1, sep = ""))
              }, error = function(e2) {
                stop(paste("Could not read file:", filename))
              })
            })
          } else {
            for (ext in c(".rds", ".csv", ".tsv", ".txt")) {
              fn <- paste0(filename, ext)
              if (file.exists(fn)) {
                if (ext == ".rds") {
                  return(readRDS(fn))
                } else if (ext == ".csv") {
                  return(read.csv(fn, row.names = 1, header = TRUE))
                } else if (ext == ".tsv") {
                  return(read.delim(fn, row.names = 1, header = TRUE))
                } else {
                  return(read.table(fn, header = TRUE, row.names = 1))
                }
              }
            }
            stop(paste("Required input file not found:", filename))
          }
        }
        
        # --- Load user inputs ---
        edata <- as.matrix(load_input("edata"))
        pdata <- load_input("pdata")
        
        # Ensure correct factor formatting for design and random effects
        pdata\$batch <- as.factor(pdata\$batch)
        pdata\$tissue <- as.factor(pdata\$tissue)
        pdata\$individual <- as.factor(pdata\$individual)
        
        # Prepare data structures for correlation estimation
        df1 <- data.frame(pdata, d1 = edata[1,])
        spl1 <- split(1:nrow(pdata), pdata\$batch)
        
        # Define the covariance estimation function (exactly as documented)
        covs1 <- function(., df1, i){
          df1\$d1 <- .
          me1 <- lme(d1 ~ tissue, data = df1[i,], random = ~1|individual)
          getVarCov(me1, type = "marginal")[[1]]
        }
        
        # Estimate the correlation matrix (cormat) between sample replicates within batches
        covs1 <- sapply(spl1,
                        function(samps)rowMeans(apply(edata, 1, covs1, df1, samps)))
        
        # Dynamically determine the size of the covariance matrix and construct cormat
        cov_size <- sqrt(nrow(covs1))
        cov1 <- matrix(rowMeans(covs1), cov_size, cov_size)
        cormat_base <- cov2cor(cov1)
        
        # Reconstruct the block-diagonal correlation matrix list for each batch
        # robustly matching the actual sample order
        cormat <- list()
        rho <- if (nrow(cormat_base) > 1) cormat_base[1, 2] else 0
        for (b in names(spl1)) {
          inds <- pdata\$individual[spl1[[b]]]
          batch_cormat <- outer(inds, inds, "==") * rho
          diag(batch_cormat) <- 1
          cormat[[b]] <- batch_cormat
        }
        cormat <- unname(cormat)
        
        # --- Create the design model matrix ---
        mod1 <- model.matrix(~1+tissue, pdata)
        
        # --- Initialize the batch random rotation object ---
        rr1 <- initBatchRandrot(Y = edata, X = mod1, coef.h = 2, batch = pdata\$batch,
                                cormat = cormat)
        
        # --- Define the custom statistic function (exactly as ---
        statistic <- function(Y, batch, mod, df1){
          Y <- limma::removeBatchEffect(Y, batch = batch, design = mod)
          apply(Y, 1, function(j){
            df1\$d1 <- j
            me0 <- nlme::lme(d1 ~ 1, data = df1, random = ~1|individual, method = "ML")
            me1 <- nlme::lme(d1 ~ tissue, data = df1, random = ~1|individual, method = "ML")
            abs(coef(me1)[1,2] / (sqrt(vcov(me1)[2,2])))
          })
        }
        
        # --- Run the rotation using rotateStat and calculate p-values ---
        rs1 <- rotateStat(initialised.obj = rr1, R = 20, statistic = statistic, 
                          batch = pdata\$batch, mod = mod1, df1 = df1, parallel = TRUE)
        p1 <- pFdr(rs1)
        
        # --- Write output files ---
        # Save p-values to CSV
        p_df <- data.frame(Feature = rownames(edata), p_value = p1)
        write.csv(p_df, "p_values.csv", row.names = FALSE)
        
        # Save p-value distribution plot to PDF
        pdf("p_values_histogram.pdf")
        hist(p1, freq = FALSE, main = "Histogram of p-values (Random Rotation)", xlab = "p-value", col = "lightgreen")
        abline(h = 1, lty = 2, lwd = 2, col = "blue")
        dev.off()
        
        # Save the complete results object to RDS
        saveRDS(list(rs1 = rs1, p1 = p1), "randrot_results.rds")

    writeLines(c(
        '"BIOC_RANDROTATION_MIXED_MODEL_BATCH_CORRECTION":',
        paste0('    randRotation: ', as.character(packageVersion('randRotation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mixed_model_batch_correction.csv versions.yml
    """
}

workflow BIOC_RANDROTATION_MIXED_MODEL_BATCH_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ edata, pdata ] ]

    main:
    BIOC_RANDROTATION_MIXED_MODEL_BATCH_CORRECTION(ch_input)

    emit:
    tables   = BIOC_RANDROTATION_MIXED_MODEL_BATCH_CORRECTION.out.tables
    plots    = BIOC_RANDROTATION_MIXED_MODEL_BATCH_CORRECTION.out.plots
    objects  = BIOC_RANDROTATION_MIXED_MODEL_BATCH_CORRECTION.out.objects
    versions = BIOC_RANDROTATION_MIXED_MODEL_BATCH_CORRECTION.out.versions
}
