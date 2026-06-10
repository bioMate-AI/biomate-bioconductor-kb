#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: powerTCR — discrete_gamma_gpd_spliced_threshold_analysis
// Fit the discrete gamma-GPD spliced threshold model to TCR clone size data, perform comparative clustering, estimate diversity, and run bootstrapping.
// Input: sample_tcr_repertoire.txt
// Container: quay.io/biocontainers/bioconductor-powertcr:1.30.0--r45hdfd78af_0
// R packages: magrittr, powerTCR, purrr, vegan
// Bioconductor: 3.20 | R: 4.4
// Requires: magrittr, powerTCR, purrr, vegan
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Parse TCR files using parseFile or parseFolder
//  * 2. [Core Analysis] Fit the discrete gamma-GPD spliced threshold model using fdiscgammagpd
//  * 3. [Core Analysis] Extract MLEs and negative log-likelihoods using get_mle and get_nllh
//  * 4. [Core Analysis] Compute theoretical quantiles using qdiscgammagpd and simulate data using rdiscgammagpd
//  * 5. [Core Analysis] Compute pairwise Jensen-Shannon distances using get_distances with modelType="Spliced"
//  * 6. [Visualization & Output] Perform hierarchical clustering and plot using clusterPlot
//  * 7. [Core Analysis] Extract diversity estimators using get_diversity
//  * 8. [Core Analysis] Run parametric bootstrapping using get_bootstraps

nextflow.enable.dsl = 2

process BIOC_POWERTCR_DISCRETE_GAMMA_GPD_SPLICED_THRESHOLD_ANALYSIS {
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
    .bm_deps <- c("magrittr", "powerTCR", "purrr", "vegan")
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
            library(powerTCR)
            library(vegan)
            library(magrittr)
            library(purrr)
            
            # 1. Parse TCR files
            input_file <- "sample_tcr_repertoire.txt"
            if (!file.exists(input_file)) {
              stop(paste("Required input file missing:", input_file))
            }
            
            # Robust parsing of the input file
            clone_sizes <- tryCatch({
              # Try parsing using powerTCR's parseFile wrapper
              parseFile(input_file)
            }, error = function(e) {
              # Fallback: Try reading as a simple vector of numbers
              val <- tryCatch(scan(input_file, quiet = TRUE), error = function(err) NULL)
              if (length(val) > 0 && is.numeric(val)) {
                return(val)
              } else {
                # Fallback: Try reading as a table and extracting the first numeric column
                df <- read.table(input_file, header = TRUE, sep = "\t")
                num_cols <- sapply(df, is.numeric)
                if (any(num_cols)) {
                  return(df[[which(num_cols)[1]]])
                } else {
                  stop("Could not parse clone sizes from file.")
                }
              }
            })
            
            # Clean and prepare clone sizes
            clone_sizes <- as.numeric(clone_sizes)
            clone_sizes <- clone_sizes[!is.na(clone_sizes) & clone_sizes >= 1]
            
            # To perform comparative analysis, we bootstrap the single repertoire into two samples
            set.seed(123)
            n_total <- length(clone_sizes)
            if (n_total < 20) {
              # Replicate if the input dataset is too small for quantile evaluation
              clone_sizes <- rep(clone_sizes, length.out = 100)
              n_total <- length(clone_sizes)
            }
            
            samp1 <- sort(sample(clone_sizes, n_total, replace = TRUE), decreasing = TRUE)
            samp2 <- sort(sample(clone_sizes, n_total, replace = TRUE), decreasing = TRUE)
            repertoires <- list("samp1" = samp1, "samp2" = samp2)
            
            # 2. Fit the discrete gamma-GPD spliced threshold model
            fits <- list()
            for(i in seq_along(repertoires)){
                thresholds <- unique(round(quantile(repertoires[[i]], c(.75,.8,.85,.9))))
                if (length(thresholds) == 0 || any(is.na(thresholds))) {
                    thresholds <- c(2, 3, 4) # Safe fallback thresholds
                }
                fits[[i]] <- fdiscgammagpd(repertoires[[i]], useq = thresholds,
                                           shift = min(repertoires[[i]]))
            }
            names(fits) <- names(repertoires)
            
            # 3. Extract MLEs and negative log-likelihoods
            mles_extracted <- get_mle(fits)
            nllh_extracted <- get_nllh(fits)
            
            # Save MLEs and NLLHs to CSV
            mles_df <- do.call(rbind, mles_extracted)
            write.csv(mles_df, "mle_estimates.csv", row.names = TRUE)
            
            nllh_df <- data.frame(Sample = names(nllh_extracted), NLLH = unlist(nllh_extracted))
            write.csv(nllh_df, "nllh_values.csv", row.names = FALSE)
            
            # 4. Compute theoretical quantiles and simulate data
            n1 <- length(repertoires[[1]])
            n2 <- length(repertoires[[2]])
            q1 <- seq(n1/(n1+1), 1/(n1+1), length.out = n1)
            q2 <- seq(n2/(n2+1), 1/(n2+1), length.out = n2)
            theor1 <- qdiscgammagpd(q1, fits[[1]])
            theor2 <- qdiscgammagpd(q2, fits[[2]])
            
            # Save theoretical quantiles
            write.csv(data.frame(theor1 = theor1), "theoretical_quantiles_samp1.csv", row.names = FALSE)
            write.csv(data.frame(theor2 = theor2), "theoretical_quantiles_samp2.csv", row.names = FALSE)
            
            # Simulate 3 sampled repertoires
            set.seed(123)
            s1 <- rdiscgammagpd(1000, shape = 3, rate = .15, u = 25, sigma = 15,
                                xi = .5, shift = 1)
            s2 <- rdiscgammagpd(1000, shape = 3.1, rate = .14, u = 26, sigma = 15,
                                xi = .6, shift = 1)
            s3 <- rdiscgammagpd(1000, shape = 10, rate = .3, u = 45, sigma = 20,
                                xi = .7, shift = 1)
            
            # 5. Compute pairwise Jensen-Shannon distances
            sim_fits <- list("s1" = fdiscgammagpd(s1, useq = 25),
                             "s2" = fdiscgammagpd(s2, useq = 26),
                             "s3" = fdiscgammagpd(s3, useq = 45))
            grid <- min(unlist(repertoires)):10000
            distances <- get_distances(fits, grid, modelType="Spliced")
            
            # Save distances
            write.csv(as.data.frame(distances), "js_distances.csv", row.names = TRUE)
            
            # 6. Perform hierarchical clustering and plot
            pdf("dendrogram.pdf")
            clusterPlot(distances, method = "ward.D")
            dev.off()
            
            # 7. Extract diversity estimators
            diversity_est <- get_diversity(fits)
            write.csv(as.data.frame(diversity_est), "diversity_estimators.csv", row.names = TRUE)
            
            # 8. Run parametric bootstrapping
            boot <- get_bootstraps(fits, resamples = 5, cores = 1, gridStyle = "copy")
            
            # Save fits and bootstrap results to RDS
            saveRDS(list(fits = fits, boot = boot), "fits_and_bootstrap.rds")
            
            # Compute confidence intervals for xi
            mles <- get_mle(boot[[1]])
            xi_CI <- map(mles, 'xi') %>% 
                unlist %>%
                quantile(c(.025,.5,.975))
            
            # Save bootstrap confidence intervals
            write.csv(data.frame(Quantile = names(xi_CI), Value = as.numeric(xi_CI)), "bootstrap_xi_ci.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_POWERTCR_DISCRETE_GAMMA_GPD_SPLICED_THRESHOLD_ANALYSIS":',
        paste0('    powerTCR: ', as.character(packageVersion('powerTCR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_discrete_gamma_gpd_spliced_threshold_analysis.csv versions.yml
    """
}

workflow BIOC_POWERTCR_DISCRETE_GAMMA_GPD_SPLICED_THRESHOLD_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_tcr_repertoire.txt ] ]

    main:
    BIOC_POWERTCR_DISCRETE_GAMMA_GPD_SPLICED_THRESHOLD_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_POWERTCR_DISCRETE_GAMMA_GPD_SPLICED_THRESHOLD_ANALYSIS.out.tables
    plots    = BIOC_POWERTCR_DISCRETE_GAMMA_GPD_SPLICED_THRESHOLD_ANALYSIS.out.plots
    objects  = BIOC_POWERTCR_DISCRETE_GAMMA_GPD_SPLICED_THRESHOLD_ANALYSIS.out.objects
    versions = BIOC_POWERTCR_DISCRETE_GAMMA_GPD_SPLICED_THRESHOLD_ANALYSIS.out.versions
}
