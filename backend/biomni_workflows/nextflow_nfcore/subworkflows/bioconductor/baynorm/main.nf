#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bayNorm — standard_baynorm_normalization
// Estimate cell-specific capture efficiencies and perform Bayesian normalization on scRNA-seq count data to generate 3D posterior samples or 2D MAP/mean matrices.
// Input: rse
// Container: quay.io/biocontainers/bioconductor-baynorm:1.28.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, SummarizedExperiment, bayNorm
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate cell-specific capture efficiencies using BetaFun
//  * 2. [Core Analysis] Run bayNorm to perform normalization and generate a 3D array of posterior samples

nextflow.enable.dsl = 2

process BIOC_BAYNORM_STANDARD_BAYNORM_NORMALIZATION {
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
    .bm_deps <- c("bayNorm")
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
        library(bayNorm)
        
        # 1. Read User Input
        # The pipeline expects a SummarizedExperiment or SingleCellExperiment object named 'rse'
        # saved as an RDS file in the working directory.
        if (file.exists("rse.rds")) {
            rse <- readRDS("rse.rds")
        } else if (file.exists("rse")) {
            rse <- readRDS("rse")
        } else {
            stop("Error: Input file 'rse' or 'rse.rds' not found in the working directory.")
        }
        
        # 2. Estimate cell-specific capture efficiencies using BetaFun
        BETA_est<-BetaFun(Data=rse,MeanBETA=0.06)
        
        # Save BETA estimates to CSV
        beta_df <- data.frame(
            Cell = colnames(rse),
            Beta = BETA_est\$BETA
        )
        write.csv(beta_df, "beta_estimates.csv", row.names = FALSE)
        
        # Generate a PDF plot of the estimated capture efficiencies
        pdf("capture_efficiencies_plot.pdf", width = 6, height = 5)
        hist(BETA_est\$BETA, 
             main = "Estimated Cell-Specific Capture Efficiencies", 
             xlab = "Capture Efficiency (Beta)", 
             col = "skyblue", 
             border = "white")
        dev.off()
        
        # 3. Run bayNorm to perform normalization and generate a 3D array of posterior samples
        bayNorm_3D<-bayNorm(
            Data=rse,
            BETA_vec = BETA_est\$BETA,
            mode_version=FALSE,
            mean_version = FALSE,S=20
            ,verbose =FALSE,
            parallel = TRUE)
        
        # Save the 3D bayNorm output object
        saveRDS(bayNorm_3D, "bayNorm_3D.rds")
        
        # 4. Generate 2D MAP and Mean matrices using bayNorm_sup
        bayNorm_2D_MAP<-bayNorm_sup(
            Data=rse,
            PRIORS=bayNorm_3D\$PRIORS,
            input_params=bayNorm_3D\$input_params,
            mode_version=TRUE,
            mean_version = FALSE,
            verbose =FALSE)
        
        bayNorm_2D_Mean<-bayNorm_sup(
            Data=rse,
            PRIORS=bayNorm_3D\$PRIORS,
            input_params=bayNorm_3D\$input_params,
            mode_version=FALSE,
            mean_version = TRUE,
            verbose =FALSE)
        
        # Save 2D normalized matrices to CSV
        write.csv(as.matrix(bayNorm_2D_MAP\$Bay_out), "normalized_MAP.csv")
        write.csv(as.matrix(bayNorm_2D_Mean\$Bay_out), "normalized_Mean.csv")
        
        cat("bayNorm pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_BAYNORM_STANDARD_BAYNORM_NORMALIZATION":',
        paste0('    bayNorm: ', as.character(packageVersion('bayNorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_baynorm_normalization.csv versions.yml
    """
}

workflow BIOC_BAYNORM_STANDARD_BAYNORM_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rse ] ]

    main:
    BIOC_BAYNORM_STANDARD_BAYNORM_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_BAYNORM_STANDARD_BAYNORM_NORMALIZATION.out.tables
    plots    = BIOC_BAYNORM_STANDARD_BAYNORM_NORMALIZATION.out.plots
    objects  = BIOC_BAYNORM_STANDARD_BAYNORM_NORMALIZATION.out.objects
    versions = BIOC_BAYNORM_STANDARD_BAYNORM_NORMALIZATION.out.versions
}
