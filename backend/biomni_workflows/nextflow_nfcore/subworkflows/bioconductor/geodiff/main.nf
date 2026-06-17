#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeoDiff — geomx_dsp_rna_workflow
// Perform background modeling, probe aggregation, target/sample QC, Poisson threshold normalization, and differential expression analysis on NanoString GeoMx DSP 
// Input: kidney
// Container: quay.io/biocontainers/bioconductor-geodiff:1.16.0--r45ha27e39d_0
// R packages: Biobase, GeomxTools, NanoStringNCTools, dplyr, GeoDiff, ggplot2, reshape2
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GeoDiff, GeomxTools, NanoStringNCTools, dplyr, ggplot2, reshape2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Update the GeoMxSet object to the current version using updateGeoMxSet
//  * 2. [Core Analysis] Fit the Poisson background model using negative probes with fitPoisBG and diagnose dispersion with diagPoisBG
//  * 3. [Core Analysis] Aggregate and filter probes based on correlation or score tests using aggreprobe
//  * 4. [Core Analysis] Perform target QC using the background score test with BGScoreTest
//  * 5. [Core Analysis] Estimate signal size factors using the negative binomial threshold model with fitNBth
//  * 6. [Core Analysis] Perform sample QC by filtering low-signal ROIs
//  * 7. [Core Analysis] Fit differential expression models using fixed effects (fitNBthDE) or mixed effects (fitNBthmDE)
//  * 8. [Core Analysis] Extract DE coefficients and generate tables using coefNBth and DENBth
//  * 9. [Core Analysis] Perform Poisson threshold normalization using fitPoisthNorm

nextflow.enable.dsl = 2

process BIOC_GEODIFF_GEOMX_DSP_RNA_WORKFLOW {
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
    .bm_deps <- c("Biobase", "GeomxTools", "NanoStringNCTools", "dplyr", "GeoDiff", "ggplot2", "reshape2")
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
    library(GeoDiff)
    library(dplyr)
    library(ggplot2)
    library(NanoStringNCTools)
    library(GeomxTools)
    library(Biobase)
    library(reshape2)
    
    # Read the user input file 'kidney' from the working directory
    if (file.exists("kidney.rds")) {
        kidney <- readRDS("kidney.rds")
    } else if (file.exists("kidney")) {
        kidney <- readRDS("kidney")
    } else {
        stop("Input file 'kidney' or 'kidney.rds' not found in the working directory.")
    }
    
    # Update to current NanoStringGeoMxSet version
    kidney <- updateGeoMxSet(kidney)
    
    # Dynamically identify metadata variables for slide and region
    cat_vars <- names(which(sapply(pData(kidney), function(x) {
        n_unq <- length(unique(x))
        n_unq > 1 && n_unq < nrow(pData(kidney))
    })))
    
    if (length(cat_vars) >= 2) {
        slide_var <- cat_vars[1]
        region_var <- cat_vars[2]
    } else if (length(cat_vars) == 1) {
        slide_var <- cat_vars[1]
        region_var <- cat_vars[1]
    } else {
        stop("Not enough categorical variables in metadata for analysis.")
    }
    
    meta_vars <- unique(c(slide_var, region_var))
    
    # Background Modeling
    kidney <- fitPoisBG(kidney)
    set.seed(123)
    kidney_diag <- diagPoisBG(kidney)
    kidney <- fitPoisBG(kidney, groupvar = slide_var)
    set.seed(123)
    kidney_diag <- diagPoisBG(kidney, split = TRUE)
    
    # Aggregate function
    all0probeidx <- which(rowSums(exprs(kidney)) == 0)
    if (length(all0probeidx) > 0) {
        kidney <- kidney[-all0probeidx, ]
    }
    kidney <- aggreprobe(kidney, use = "cor")
    
    # Target QC Score test
    kidney <- BGScoreTest(kidney)
    kidneySplit <- BGScoreTest(kidney, split = TRUE, removeoutlier = FALSE, useprior = FALSE)
    kidneyOutliers <- BGScoreTest(kidney, split = FALSE, removeoutlier = TRUE, useprior = FALSE)
    kidneyPrior <- BGScoreTest(kidney, split = FALSE, removeoutlier = FALSE, useprior = TRUE)
    
    # Estimate the size factor
    set.seed(123)
    kidney <- fitNBth(kidney, split = TRUE)
    features_high <- rownames(fData(kidney))[fData(kidney)\$feature_high_fitNBth == 1]
    
    bgMean <- mean(fData(kidney)\$featfact, na.rm = TRUE)
    
    # Get only biological probes
    posdat <- kidney[-which(fData(kidney)\$CodeClass == "Negative"), ]
    posdat <- exprs(posdat)
    quan75 <- apply(posdat, 2, function(x) quantile(x, probs = 0.75))
    
    kidney <- QuanRange(kidney, split = FALSE, probs = c(0.75, 0.8, 0.9, 0.95))
    
    # Sample QC
    ROIs_high <- sampleNames(kidney)[which((quantile(fData(kidney)[["para"]][, 1],
                                                      probs = 0.90, na.rm = TRUE) -
                                              notes(kidney)[["threshold"]])*kidney\$sizefact_fitNBth>2)]
    features_all <- rownames(posdat)
    
    # DE modeling Fixed Effect Model
    form_fixed <- as.formula(paste0("~ `", region_var, "`"))
    NBthDEmod <- fitNBthDE(form = form_fixed,
                           split = FALSE,
                           object = kidney)
    
    pData(kidney)[[region_var]] <- as.factor(pData(kidney)[[region_var]])
    region_levels <- levels(pData(kidney)[[region_var]])
    
    target_gene <- features_high[1]
    features_high_subset <- features_high[1:min(30, length(features_high))]
    
    # Mixed effect model
    set.seed(123)
    form_mixed <- as.formula(paste0("~ `", region_var, "` + (1 | `", slide_var, "`)"))
    NBthmDEmod <- fitNBthmDE(object = kidney,
                             form = form_mixed,
                             ROIs_high = ROIs_high,
                             split = FALSE,
                             features_all = features_high_subset,
                             preci1=NBthDEmod\$preci1,
                             threshold_mean = bgMean,
                             sizescale = TRUE,
                             controlRandom=list(nu=12, nmh_e=400, thin_e=60))
    
    set.seed(123)
    form_mixed_slope <- as.formula(paste0("~ `", region_var, "` + (1 + `", region_var, "` | `", slide_var, "`)"))
    NBthmDEmodslope <- fitNBthmDE(object = kidney,
                                  form = form_mixed_slope,
                                  ROIs_high = ROIs_high,
                                  split = FALSE,
                                  features_all = features_high_subset,
                                  preci1=NBthDEmod\$preci1,
                                  threshold_mean = bgMean,
                                  sizescale = TRUE,
                                  controlRandom=list(nu=12, nmh_e=400, thin_e=60))
    
    # Generate DE result
    coeff <- coefNBth(NBthDEmod)
    coefr <- coefNBth(NBthmDEmod)
    coefrslope <- coefNBth(NBthmDEmodslope)
    
    coef_var <- paste0(region_var, region_levels[2])
    DEtab <- DENBth(coeff, variable = coef_var)
    DEtabr <- DENBth(coefr, variable = coef_var)
    DEtabrslope <- DENBth(coefrslope, variable = coef_var)
    
    # Normalization
    set.seed(123)
    kidney <- fitPoisthNorm(object = kidney,
                            ROIs_high = ROIs_high,
                            threshold_mean = bgMean,
                            sizescalebythreshold = TRUE)
    
    set.seed(123)
    kidney <- fitPoisthNorm(object = kidney,
                            split = TRUE,
                            ROIs_high = ROIs_high,
                            threshold_mean = bgMean,
                            sizescalebythreshold = TRUE)
    
    # Write DE tables to CSV
    write.csv(DEtab, "DE_table_fixed_effect.csv", row.names = TRUE)
    write.csv(DEtabr, "DE_table_mixed_intercept.csv", row.names = TRUE)
    write.csv(DEtabrslope, "DE_table_mixed_slope.csv", row.names = TRUE)
    
    # Save the final normalized GeoMxSet object
    saveRDS(kidney, "kidney_normalized.rds")
    
    # Generate diagnostic plots and save to PDF
    pdf("geomx_dsp_rna_workflow_plots.pdf", width = 8, height = 6)
    
    # Plot 1: Background vs Signal Size Factor
    plot(kidney\$sizefact, kidney\$sizefact_fitNBth, xlab = "Background Size Factor",
         ylab = "Signal Size Factor", main = "Background vs Signal Size Factor")
    abline(a = 0, b = 1)
    
    # Plot 2: Boxplot of target_gene
    annot <- pData(kidney)
    annot[[target_gene]] <- posdat[target_gene, ]
    plot_dat <- annot[, unique(c(region_var, target_gene, slide_var))]
    p1 <- ggplot(plot_dat, aes(x = .data[[slide_var]], y = .data[[target_gene]], fill = .data[[region_var]])) +
      geom_boxplot() +
      theme_bw() +
      ggtitle(paste(target_gene, "Expression by Slide and Region"))
    print(p1)
    
    # Plot 3: Q3 Normalization Density
    norm_dat_backqu75 <- sweep(posdat[, ROIs_high], 2,
                               (kidney[, ROIs_high]\$sizefact * bgMean),
                               FUN = "-") %>%
      sweep(., 2, quan75[ROIs_high], FUN = "/") %>%
      pmax(., 0) %>%
      `+`(., 0.01) %>%
      log2()
    
    dat_plot_q3 <- cbind(pData(kidney)[ROIs_high, meta_vars, drop = FALSE],
                        t(norm_dat_backqu75[features_all, ]))
    dat_plot_q3 <- cbind(dat_plot_q3, ROI_ID = ROIs_high)
    dat_plot_q3 <- melt(dat_plot_q3, id.vars = c("ROI_ID", meta_vars))
    
    p2 <- ggplot(dat_plot_q3, aes(x = value)) +
      geom_density(aes(fill = .data[[region_var]], group = ROI_ID), alpha = 0.01) +
      facet_grid(as.formula(paste0("~ `", slide_var, "`"))) +
      ggtitle("Q3 Normalization") +
      labs(x = "Q3 Normalized Value (log2)")
    print(p2)
    
    # Plot 4: Poisson Threshold Normalization Density
    dat_plot_pois <- cbind(annot[ROIs_high, meta_vars, drop = FALSE],
                          t(assayDataElement(kidney[features_high, ROIs_high], "normmat_sp")))
    dat_plot_pois <- cbind(dat_plot_pois, ROI_ID = ROIs_high)
    dat_plot_pois <- melt(dat_plot_pois, id.vars = c("ROI_ID", meta_vars))
    
    p3 <- ggplot(dat_plot_pois, aes(x = value)) +
      geom_density(aes(fill = .data[[region_var]], group = ROI_ID), alpha = 0.01) +
      facet_wrap(as.formula(paste0("~ `", slide_var, "`"))) +
      ggtitle("Poisson Threshold Normalization") +
      labs(x = "Poisson Threshold Normalized Value (log2)")
    print(p3)
    
    # Plot 5: PCA Q3 Normalized Data
    dat_q3 <- t(norm_dat_backqu75[features_high, ])
    dat_pca_q3 <- prcomp(dat_q3, center = TRUE, scale. = TRUE)
    df_q3 <- as.data.frame(dat_q3)
    df_q3\$PC1 <- dat_pca_q3\$x[, 1]
    df_q3\$PC2 <- dat_pca_q3\$x[, 2]
    df_q3[[region_var]] <- annot[[region_var]][match(ROIs_high, colnames(posdat))]
    
    if ("class" %in% colnames(annot)) {
        df_q3\$class <- annot\$class[match(ROIs_high, colnames(posdat))]
        df_q3\$color_var <- paste(df_q3\$class, df_q3[[region_var]])
    } else {
        df_q3\$color_var <- as.character(df_q3[[region_var]])
    }
    
    p4 <- ggplot(data = df_q3, aes(x = PC1, y = PC2)) +
      geom_point(aes(colour = color_var)) +
      theme_bw() +
      labs(title = "Q3 Normalized Data", colour = "Group")
    print(p4)
    
    # Plot 6: PCA Poisson Threshold Normalized Data
    dat_pois <- t(assayDataElement(kidney[features_high, ROIs_high], "normmat_sp"))
    dat_pca_pois <- prcomp(dat_pois, center = TRUE, scale. = TRUE)
    df_pois <- as.data.frame(dat_pois)
    df_pois\$PC1 <- dat_pca_pois\$x[, 1]
    df_pois\$PC2 <- dat_pca_pois\$x[, 2]
    df_pois[[region_var]] <- annot[[region_var]][match(ROIs_high, colnames(posdat))]
    
    if ("class" %in% colnames(annot)) {
        df_pois\$class <- annot\$class[match(ROIs_high, colnames(posdat))]
        df_pois\$color_var <- paste(df_pois\$class, df_pois[[region_var]])
    } else {
        df_pois\$color_var <- as.character(df_pois[[region_var]])
    }
    
    p5 <- ggplot(data = df_pois, aes(x = PC1, y = PC2)) +
      geom_point(aes(colour = color_var)) +
      theme_bw() +
      labs(title = "Poisson Threshold Normalized Data", colour = "Group")
    print(p5)
    
    dev.off()

    writeLines(c(
        '"BIOC_GEODIFF_GEOMX_DSP_RNA_WORKFLOW":',
        paste0('    GeoDiff: ', as.character(packageVersion('GeoDiff')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geomx_dsp_rna_workflow.csv versions.yml
    """
}

workflow BIOC_GEODIFF_GEOMX_DSP_RNA_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kidney ] ]

    main:
    BIOC_GEODIFF_GEOMX_DSP_RNA_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_GEODIFF_GEOMX_DSP_RNA_WORKFLOW.out.tables
    plots    = BIOC_GEODIFF_GEOMX_DSP_RNA_WORKFLOW.out.plots
    objects  = BIOC_GEODIFF_GEOMX_DSP_RNA_WORKFLOW.out.objects
    versions = BIOC_GEODIFF_GEOMX_DSP_RNA_WORKFLOW.out.versions
}
