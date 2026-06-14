#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rexposome — standard_exposome_analysis
// Load standard exposome data, pre-process it, explore relationships, and perform association studies (ExWAS, Inverse ExWAS, and Elastic Net).
// Input: description.csv, exposures.csv, phenotypes.csv
// Container: quay.io/biocontainers/bioconductor-rexposome:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, rexposome
// Visualizations: PCA plot, correlation plot, circos plot
// QC: diagnostic MA/PCA QC, missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data using readExposome or loadExposome
//  * 2. [Core Analysis] Assess missingness and normality
//  * 3. [Core Analysis] Impute missing values
//  * 4. [Core Analysis] Standardize and perform PCA/FAMD
//  * 5. [Core Analysis] Compute exposure correlations and cluster individuals
//  * 6. [Core Analysis] Run univariate ExWAS, Inverse ExWAS, and multivariate mexwas

nextflow.enable.dsl = 2

process BIOC_REXPOSOME_STANDARD_EXPOSOME_ANALYSIS {
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
    .bm_deps <- c("rexposome", "ggplot2")
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
        
    library(rexposome)
    library(ggplot2)
    
    # 1. Load standard exposome data from the working directory
    description <- "description.csv"
    phenotype <- "phenotypes.csv"
    exposures <- "exposures.csv"
    
    # Dynamically determine column names to avoid hardcoding
    desc_cols <- colnames(read.csv(description, nrows = 1))
    exp_cols <- colnames(read.csv(exposures, nrows = 1))
    phe_cols <- colnames(read.csv(phenotype, nrows = 1))
    
    exp <- readExposome(
      exposures = exposures, 
      description = description, 
      phenotype = phenotype, 
      exposures.samCol = exp_cols[1], 
      description.expCol = desc_cols[1], 
      description.famCol = desc_cols[2], 
      phenotype.samCol = phe_cols[1]
    )
    
    # Dynamically select exposures and phenotypes to avoid hardcoding
    exp_names <- exposureNames(exp)
    phe_names <- phenotypeNames(exp)
    
    hist_exp <- exp_names[1]
    pca_phe <- phe_names[1]
    
    p_data <- pData(exp)
    num_phes <- names(p_data)[sapply(p_data, is.numeric)]
    bin_phes <- names(p_data)[sapply(p_data, function(x) length(unique(na.omit(x))) == 2)]
    
    phe_out1 <- if(length(num_phes) > 0) num_phes[1] else phe_names[1]
    fam1 <- if(length(num_phes) > 0) "gaussian" else "binomial"
    
    if (length(bin_phes) > 0) {
      phe_out2 <- bin_phes[1]
      fam2 <- "binomial"
    } else if (length(num_phes) > 1) {
      phe_out2 <- num_phes[2]
      fam2 <- "gaussian"
    } else {
      phe_out2 <- phe_names[1]
      fam2 <- "gaussian"
    }
    
    avail_covs <- setdiff(phe_names, c(phe_out1, phe_out2))
    covs_str <- if(length(avail_covs) > 0) paste(avail_covs[1:min(2, length(avail_covs))], collapse = " + ") else "1"
    
    form1 <- as.formula(paste(phe_out1, "~", covs_str))
    form2 <- as.formula(paste(phe_out2, "~", covs_str))
    form_inv <- as.formula(paste("~", phe_out1, if(length(avail_covs) > 0) paste("+", avail_covs[1]) else ""))
    
    # 2. Assess missingness and normality
    miss_exp <- tableMissings(exp, set = "exposures", output = "n")
    miss_phe <- tableMissings(exp, set = "phenotypes", output = "n")
    
    write.csv(as.data.frame(miss_exp), "missingness_exposures.csv", row.names = TRUE)
    write.csv(as.data.frame(miss_phe), "missingness_phenotypes.csv", row.names = TRUE)
    
    pdf("plot_missings_exposures.pdf")
    print(plotMissings(exp, set = "exposures"))
    dev.off()
    
    nm <- normalityTest(exp)
    write.csv(nm, "normality_test_results.csv", row.names = FALSE)
    
    pdf(paste0("plot_histogram_", hist_exp, ".pdf"))
    p_hist <- plotHistogram(exp, select = hist_exp) + ggtitle(paste("Histogram of", hist_exp))
    print(p_hist)
    dev.off()
    
    # 3. Impute missing values
    exp <- imputation(exp)
    
    # 4. Standardize and perform PCA/FAMD
    pdf("plot_family_all.pdf")
    print(plotFamily(exp, family = "all"))
    dev.off()
    
    exp_std <- standardize(exp, method = "normal")
    exp_pca <- pca(exp_std, pca = TRUE)
    saveRDS(exp_pca, "exposome_pca.rds")
    
    pdf("plot_pca_all.pdf")
    print(plotPCA(exp_pca, set = "all"))
    dev.off()
    
    pdf(paste0("plot_pca_samples_", pca_phe, ".pdf"))
    print(plotPCA(exp_pca, set = "samples", phenotype = pca_phe))
    dev.off()
    
    # plot3PCA generates an interactive rgl plot, which cannot be saved directly to a PDF device
    tryCatch({
      plot3PCA(exp_pca, cmpX=1, cmpY=2, cmpZ=3, phenotype = pca_phe)
    }, error = function(e) {
      message("Warning: plot3PCA failed: ", e\$message)
    })
    
    # 5. Compute exposure correlations and cluster individuals
    exp_cr <- correlation(exp, use = "pairwise.complete.obs", method.cor = "pearson")
    write.csv(extract(exp_cr), "exposure_correlation_matrix.csv", row.names = TRUE)
    
    pdf("plot_correlation_circos.pdf")
    plotCorrelation(exp_cr, type = "circos")
    dev.off()
    
    hclust_data <- function(data, ...) { hclust(d = dist(x = data), ...) }
    hclust_k3 <- function(result) { cutree(result, k = 3) }
    exp_c <- clustering(exp, method = hclust_data, cmethod = hclust_k3)
    saveRDS(exp_c, "exposome_clustering.rds")
    
    pdf("plot_classification.pdf")
    print(plotClassification(exp_c))
    dev.off()
    
    pdf("plot_pca_exp_correlation.pdf")
    p_exp <- plotEXP(exp_pca) + theme(axis.text.y = element_text(size = 6.5)) + ylab("")
    print(p_exp)
    dev.off()
    
    pdf("plot_pca_phe_association.pdf")
    print(plotPHE(exp_pca))
    dev.off()
    
    # 6. Run univariate ExWAS, Inverse ExWAS, and multivariate mexwas
    fl_ew <- exwas(exp, formula = form1, family = fam1)
    we_ew <- exwas(exp, formula = form2, family = fam2)
    
    write.csv(extract(fl_ew), paste0("exwas_", phe_out1, "_results.csv"), row.names = TRUE)
    write.csv(extract(we_ew), paste0("exwas_", phe_out2, "_results.csv"), row.names = TRUE)
    
    clr <- rainbow(length(familyNames(exp)))
    names(clr) <- familyNames(exp)
    
    pdf("plot_exwas_univariate.pdf")
    p_exwas <- plotExwas(fl_ew, we_ew, color = clr) + ggtitle("Exposome Association Study - Univariate Approach")
    print(p_exwas)
    dev.off()
    
    pdf("plot_exwas_effect.pdf")
    print(plotEffect(fl_ew))
    dev.off()
    
    inv_ex <- invExWAS(exp, formula = form_inv)
    write.csv(extract(inv_ex), "inverse_exwas_results.csv", row.names = TRUE)
    
    bl_mew <- mexwas(exp_std, phenotype = phe_out1, family = fam1)
    we_mew <- mexwas(exp_std, phenotype = phe_out2, family = fam2)
    
    # extract() is not supported for mexwas objects, so we only plot the results
    
    pdf("plot_exwas_multivariate.pdf")
    p_mexwas <- plotExwas(bl_mew, we_mew) + ylab("") + ggtitle("Exposome Association Study - Multivariate Approach")
    print(p_mexwas)
    dev.off()

    writeLines(c(
        '"BIOC_REXPOSOME_STANDARD_EXPOSOME_ANALYSIS":',
        paste0('    rexposome: ', as.character(packageVersion('rexposome')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_exposome_analysis.csv versions.yml
    """
}

workflow BIOC_REXPOSOME_STANDARD_EXPOSOME_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ description.csv, exposures.csv, phenotypes.csv ] ]

    main:
    BIOC_REXPOSOME_STANDARD_EXPOSOME_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_REXPOSOME_STANDARD_EXPOSOME_ANALYSIS.out.tables
    plots    = BIOC_REXPOSOME_STANDARD_EXPOSOME_ANALYSIS.out.plots
    objects  = BIOC_REXPOSOME_STANDARD_EXPOSOME_ANALYSIS.out.objects
    versions = BIOC_REXPOSOME_STANDARD_EXPOSOME_ANALYSIS.out.versions
}
