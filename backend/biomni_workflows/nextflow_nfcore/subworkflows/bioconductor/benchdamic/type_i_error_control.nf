#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: benchdamic — type_i_error_control
// Evaluate the ability of various DA methods to control false positives using mock comparisons.
// Input: ps_stool_16S
// Container: quay.io/biocontainers/bioconductor-benchdamic:1.6.0--r43hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, benchdamic, ggplot2, phyloseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create mock groups by randomly assigning homogeneous samples
//  * 2. [Input & Preparation] Set up and run normalizations
//  * 3. [Core Analysis] Filter rare taxa
//  * 4. [Core Analysis] Compute zero-inflated negative binomial weights
//  * 5. [Input & Preparation] Set up DA methods and run them on mock comparisons
//  * 6. [Visualization & Output] Summarize Type I Error Control (TIEC) metrics
//  * 7. [Visualization & Output] Plot False Positive Rate (FPR), False Discovery Rate (FDR), QQ-plots, Kolmogorov-Smirnov statistics, and p-value log distributions

nextflow.enable.dsl = 2

process BIOC_BENCHDAMIC_TYPE_I_ERROR_CONTROL {
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
    .bm_deps <- c("benchdamic", "phyloseq", "BiocParallel", "ggplot2")
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
    library(benchdamic)
    library(phyloseq)
    library(BiocParallel)
    library(ggplot2)
    
    # 1. Read the input file from the working directory
    if (file.exists("ps_stool_16S")) {
        ps_stool_16S <- readRDS("ps_stool_16S")
    } else if (file.exists("ps_stool_16S.rds")) {
        ps_stool_16S <- readRDS("ps_stool_16S.rds")
    } else {
        stop("Error: Input file 'ps_stool_16S' or 'ps_stool_16S.rds' not found in the working directory.")
    }
    
    # Set seed for reproducibility
    set.seed(123)
    
    # 2. Create mock groups by randomly assigning homogeneous samples
    my_mocks <- createMocks(
        nsamples = phyloseq::nsamples(ps_stool_16S),
        N = 3
    )
    
    # 3. Set up and run normalizations
    my_normalizations <- setNormalizations(
        fun = c("norm_edgeR", "norm_DESeq2", "norm_CSS"), 
        method = c("TMM", "poscounts", "CSS")
    )
    
    ps_stool_16S <- runNormalizations(
        normalization_list = my_normalizations, 
        object = ps_stool_16S, 
        verbose = TRUE
    )
    
    # 4. Filter rare taxa
    ps_stool_16S <- phyloseq::filter_taxa(
        physeq = ps_stool_16S, 
        flist = function(x) sum(x > 0) >= 3, 
        prune = TRUE
    )
    
    # 5. Compute zero-inflated negative binomial weights
    zinbweights <- weights_ZINB(
        object = ps_stool_16S,
        K = 0,
        design = "~ 1"
    )
    
    # 6. Set up DA methods
    my_basic <- set_basic(
        pseudo_count = FALSE,
        contrast = c("group", "grp2", "grp1"), 
        test = c("t", "wilcox"), 
        paired = FALSE, 
        expand = TRUE
    )
    
    my_edgeR <- set_edgeR(
        pseudo_count = FALSE,
        group_name = "group",
        design = ~ group,
        robust = FALSE,
        coef = 2,
        norm = "TMM",
        weights_logical = c(TRUE, FALSE),
        expand = TRUE
    )
    
    my_methods <- c(my_basic, my_edgeR)
    
    # 7. Run DA methods on mock comparisons
    bpparam <- BiocParallel::SerialParam()
    
    Stool_16S_mockDA <- runMocks(
        mocks = my_mocks, 
        method_list = my_methods, 
        object = ps_stool_16S, 
        weights = zinbweights, 
        verbose = FALSE, 
        BPPARAM = bpparam
    )
    
    # 8. Summarize Type I Error Control (TIEC) metrics
    TIEC_summary <- createTIEC(Stool_16S_mockDA)
    
    # Save the summary data frames to CSV files
    write.csv(TIEC_summary\$df_pval, "TIEC_df_pval.csv", row.names = FALSE)
    write.csv(TIEC_summary\$df_FPR, "TIEC_df_FPR.csv", row.names = FALSE)
    write.csv(TIEC_summary\$df_FDR, "TIEC_df_FDR.csv", row.names = FALSE)
    write.csv(TIEC_summary\$df_QQ, "TIEC_df_QQ.csv", row.names = FALSE)
    write.csv(TIEC_summary\$df_KS, "TIEC_df_KS.csv", row.names = FALSE)
    
    # Save the complete TIEC summary object as RDS
    saveRDS(TIEC_summary, "TIEC_summary.rds")
    
    # 9. Generate and save plots
    cols <- createColors(variable = levels(TIEC_summary\$df_pval\$Method))
    
    # Plot False Positive Rate (FPR)
    p_fpr <- plotFPR(df_FPR = TIEC_summary\$df_FPR, cols = cols)
    ggsave("plot_FPR.pdf", plot = p_fpr, width = 8, height = 6)
    
    # Plot False Discovery Rate (FDR)
    p_fdr <- plotFDR(df_FDR = TIEC_summary\$df_FDR, cols = cols)
    ggsave("plot_FDR.pdf", plot = p_fdr, width = 8, height = 6)
    
    # Plot QQ-plot
    p_qq <- plotQQ(df_QQ = TIEC_summary\$df_QQ, zoom = c(0, 0.1), cols = cols)
    ggsave("plot_QQ.pdf", plot = p_qq, width = 8, height = 6)
    
    # Plot Kolmogorov-Smirnov statistics
    p_ks <- plotKS(df_KS = TIEC_summary\$df_KS, cols = cols)
    ggsave("plot_KS.pdf", plot = p_ks, width = 8, height = 6)
    
    # Plot p-value log distributions
    p_logp <- plotLogP(df_pval = TIEC_summary\$df_pval, cols = cols)
    ggsave("plot_LogP.pdf", plot = p_logp, width = 8, height = 6)

    writeLines(c(
        '"BIOC_BENCHDAMIC_TYPE_I_ERROR_CONTROL":',
        paste0('    benchdamic: ', as.character(packageVersion('benchdamic')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_type_i_error_control.csv versions.yml
    """
}

workflow BIOC_BENCHDAMIC_TYPE_I_ERROR_CONTROL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ps_stool_16S ] ]

    main:
    BIOC_BENCHDAMIC_TYPE_I_ERROR_CONTROL(ch_input)

    emit:
    tables   = BIOC_BENCHDAMIC_TYPE_I_ERROR_CONTROL.out.tables
    plots    = BIOC_BENCHDAMIC_TYPE_I_ERROR_CONTROL.out.plots
    objects  = BIOC_BENCHDAMIC_TYPE_I_ERROR_CONTROL.out.objects
    versions = BIOC_BENCHDAMIC_TYPE_I_ERROR_CONTROL.out.versions
}
