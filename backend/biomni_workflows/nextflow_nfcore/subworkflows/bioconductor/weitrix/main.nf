#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: weitrix — weighted_continuous_matrix_analysis
// Analyze continuous measurements with associated precision weights (e.g., average tail lengths weighted by read counts) to calibrate weights, find components of 
// Input: tail.csv.gz, tail_count.csv.gz, samples
// Container: quay.io/biocontainers/bioconductor-weitrix:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, dplyr, ggplot2, limma, topconfects, weitrix
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct weitrix using as_weitrix
//  * 2. [Core Analysis] Annotate row and column metadata
//  * 3. [Core Analysis] Fit initial components with weitrix_components
//  * 4. [Core Analysis] Calibrate weights using weitrix_calibrate_all with well_knotted_spline
//  * 5. [Visualization & Output] Diagnostic plotting with weitrix_calplot
//  * 6. [Core Analysis] Test for top confident effects using weitrix_confects or limma (via weitrix_elist)
//  * 7. [Visualization & Output] Discover components of variation using weitrix_components_seq and plot with components_seq_screeplot

nextflow.enable.dsl = 2

process BIOC_WEITRIX_WEIGHTED_CONTINUOUS_MATRIX_ANALYSIS {
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
    .bm_deps <- c("weitrix", "limma", "topconfects", "dplyr", "ggplot2", "BiocParallel", "SummarizedExperiment")
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
    library(weitrix)
    library(SummarizedExperiment)
    library(limma)
    library(topconfects)
    library(dplyr)
    library(ggplot2)
    library(BiocParallel)
    
    # Set parallel processing to serial for reliability
    BiocParallel::register(BiocParallel::SerialParam())
    
    # Set seed for reproducibility
    set.seed(12345)
    
    # 1. Read input files from the working directory
    tail <- read.csv("tail.csv.gz", row.names = 1, check.names = FALSE) %>% as.matrix()
    tail_count <- read.csv("tail_count.csv.gz", row.names = 1, check.names = FALSE) %>% as.matrix()
    samples <- read.csv("samples", row.names = 1, check.names = FALSE)
    
    # Ensure factor levels are correct and match the design dynamically
    for (col in colnames(samples)) {
      samples[[col]] <- factor(samples[[col]], levels = unique(samples[[col]]))
    }
    
    # Filter genes with sufficient read counts
    good <- rowMeans(tail_count) >= 10
    
    # 2. Construct weitrix object
    wei <- as_weitrix( tail[good,,drop=FALSE], weights=tail_count[good,,drop=FALSE])
    
    # Annotate row metadata safely (generic fallback)
    rowData(wei)\$gene <- rownames(wei)
    
    rowData(wei)\$total_reads <- rowSums(weitrix_weights(wei))
    colData(wei) <- cbind(colData(wei), samples)
    
    # 3. Fit initial components
    design <- model.matrix(~ ., data=samples)
    fit <- weitrix_components(wei, design=design)
    
    # 4. Calibrate weights
    cal <- weitrix_calibrate_all( wei, design = fit, trend_formula = ~well_knotted_spline(mu,3)+well_knotted_spline(log(weight),3))
    
    # 5. Diagnostic plotting
    unwei <- wei
    weitrix_weights(unwei) <- weitrix_weights(unwei) > 0
    
    pdf("weitrix_calplot.pdf", width = 7, height = 5)
    p1 <- weitrix_calplot(unwei, fit, covar=mu, guides=FALSE)
    print(p1)
    dev.off()
    
    # 6. Test for top confident effects
    coef_name <- colnames(design)[2]
    
    confects_strain <- weitrix_confects(cal, design, coef=coef_name, fdr=0.05)
    write.csv(confects_strain\$table, "confects_strain.csv", row.names = FALSE)
    
    confects_strain_cohen <- weitrix_confects(cal, design, coef=coef_name, effect="cohen_f", fdr=0.05)
    write.csv(confects_strain_cohen\$table, "confects_strain_cohen.csv", row.names = FALSE)
    
    # Limma analysis
    fit_cal_design <- cal %>% weitrix_elist() %>% lmFit(design)
    ebayes_fit <- eBayes(fit_cal_design)
    top_table_strain <- topTable(ebayes_fit, coef=coef_name, n=10)
    write.csv(top_table_strain, "top_table_strain.csv")
    
    # Multiple contrasts
    multiple_contrasts <- diag(ncol(design))[, -1, drop=FALSE]
    rownames(multiple_contrasts) <- colnames(design)
    colnames(multiple_contrasts) <- colnames(design)[-1]
    
    confects_multi <- weitrix_confects(cal, design, contrasts=multiple_contrasts, fdr=0.05)
    write.csv(confects_multi\$table, "confects_multi.csv", row.names = FALSE)
    
    # Overdispersion
    confects <- weitrix_sd_confects(cal, ~1)
    write.csv(confects\$table, "confects_sd.csv", row.names = FALSE)
    
    # 7. Discover components of variation
    comp_seq <- weitrix_components_seq(cal, p=6)
    
    pdf("components_screeplot.pdf", width = 7, height = 5)
    p2 <- components_seq_screeplot(comp_seq)
    print(p2)
    dev.off()
    
    comp <- comp_seq[[3]]
    saveRDS(comp, "components_3.rds")
    
    long_comp <- matrix_long(comp\$col[,-1], row_info=samples, varnames=c("sample","component"))
    write.csv(long_comp, "components_long.csv", row.names = FALSE)
    
    result_C1 <- weitrix_confects(cal, comp\$col, coef="C1")
    write.csv(result_C1\$table, "result_C1.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_WEITRIX_WEIGHTED_CONTINUOUS_MATRIX_ANALYSIS":',
        paste0('    weitrix: ', as.character(packageVersion('weitrix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_weighted_continuous_matrix_analysis.csv versions.yml
    """
}

workflow BIOC_WEITRIX_WEIGHTED_CONTINUOUS_MATRIX_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tail.csv.gz, tail_count.csv.gz, samples ] ]

    main:
    BIOC_WEITRIX_WEIGHTED_CONTINUOUS_MATRIX_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_WEITRIX_WEIGHTED_CONTINUOUS_MATRIX_ANALYSIS.out.tables
    plots    = BIOC_WEITRIX_WEIGHTED_CONTINUOUS_MATRIX_ANALYSIS.out.plots
    objects  = BIOC_WEITRIX_WEIGHTED_CONTINUOUS_MATRIX_ANALYSIS.out.objects
    versions = BIOC_WEITRIX_WEIGHTED_CONTINUOUS_MATRIX_ANALYSIS.out.versions
}
