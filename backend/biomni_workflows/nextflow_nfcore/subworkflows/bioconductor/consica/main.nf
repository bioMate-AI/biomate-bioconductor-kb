#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: consICA — consensus_ica_workflow
// Deconvolve transcriptomics data using consensus ICA, extract key features, associate components with clinical metadata and survival, perform GO enrichment, and 
// Input: samples_data, Var, Sur
// Container: quay.io/biocontainers/bioconductor-consica:2.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, consICA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and extract expression, metadata, and survival variables
//  * 2. [Core Analysis] Run consensus ICA deconvolution using consICA
//  * 3. [Core Analysis] Extract top contributing features (genes) for components using getFeatures
//  * 4. [Visualization & Output] Estimate and plot variance explained using estimateVarianceExplained and plotICVarianceExplained
//  * 5. [Core Analysis] Associate components with experimental factors using ANOVA via anovaIC
//  * 6. [Core Analysis] Perform Gene Ontology enrichment analysis using getGO
//  * 7. [Core Analysis] Perform survival analysis and calculate risk scores using survivalAnalysis
//  * 8. [Visualization & Output] Generate an automated PDF report using saveReport

nextflow.enable.dsl = 2

process BIOC_CONSICA_CONSENSUS_ICA_WORKFLOW {
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
    .bm_deps <- c("consICA", "SummarizedExperiment")
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
      library(SummarizedExperiment)
  library(consICA)
    
    # 1. Load data and extract expression, metadata, and survival variables
    # Read the user-provided files from the working directory
    samples_data <- readRDS("samples_data.rds")
    Var <- readRDS("Var.rds")
    Sur <- readRDS("Sur.rds")
    
    # Extract expression matrix
    X <- data.frame(assay(samples_data))
    
    # 2. Run consensus ICA deconvolution using consICA
    set.seed(2022)
    cica <- consICA(samples_data, ncomp = 20, ntry = 10, ncores = 1, show.every = 0)
    
    # 3. Extract top contributing features (genes) for components using getFeatures
    features <- getFeatures(cica, alpha = 0.05, sort = TRUE)
    
    # Save extracted features to CSV files
    write.csv(features\$ic.1\$pos, "features_ic1_pos.csv", row.names = TRUE)
    write.csv(features\$ic.1\$neg, "features_ic1_neg.csv", row.names = TRUE)
    saveRDS(features, "extracted_features.rds")
    
    # Plot metagene involvement for the first component
    pdf("metagene_involvement_ic1.pdf", width = 7, height = 5)
    icomp <- 1
    plot(
      sort(cica\$S[, icomp]),
      col = "#0000FF",
      type = "l",
      ylab = "involvement",
      xlab = "genes",
      las = 2,
      cex.axis = 0.4,
      main = paste0("Metagene #", icomp, "\n(involvement of features)"),
      cex.main = 0.6
    )
    dev.off()
    
    # 4. Estimate and plot variance explained using estimateVarianceExplained and plotICVarianceExplained
    var_ic <- estimateVarianceExplained(cica)
    saveRDS(var_ic, "variance_explained.rds")
    
    pdf("ic_variance_explained.pdf", width = 7, height = 5)
    p <- plotICVarianceExplained(cica)
    if (inherits(p, "ggplot") || inherits(p, "gtable")) {
      plot(p)
    }
    dev.off()
    
    # 5. Associate components with experimental factors using ANOVA via anovaIC
    pdf("anova_ic1_plot.pdf", width = 8, height = 6)
    var_ic1 <- anovaIC(cica, Var, icomp = 1, color_by_pv = TRUE, plot = TRUE)
    dev.off()
    
    var_ic5 <- anovaIC(cica, Var, icomp = 5, mode = 'box', plot = FALSE)
    
    # Save ANOVA results
    write.csv(var_ic1, "anova_results_ic1.csv", row.names = TRUE)
    write.csv(var_ic5, "anova_results_ic5.csv", row.names = TRUE)
    
    # 6. Perform Gene Ontology enrichment analysis using getGO
    # Run GO enrichment for Biological Processes (BP)
    cica <- getGO(cica, alpha = 0.05, db = "BP", ncores = 1)
    
    # 7. Perform survival analysis and calculate risk scores using survivalAnalysis
    RS <- survivalAnalysis(cica, surv = Sur)
    
    # Save survival analysis results
    saveRDS(RS, "survival_analysis_results.rds")
    if (!is.null(RS\$hazard.score)) {
      write.csv(as.data.frame(t(RS\$hazard.score)), "survival_hazard_scores.csv", row.names = FALSE)
    }
    
    # 8. Generate an automated PDF report using saveReport
    saveReport(cica, Var = Var, surv = Sur)
    
    # Save final consensus ICA object with GO annotations
    saveRDS(cica, "cica_final_results.rds")

    writeLines(c(
        '"BIOC_CONSICA_CONSENSUS_ICA_WORKFLOW":',
        paste0('    consICA: ', as.character(packageVersion('consICA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_consensus_ica_workflow.csv versions.yml
    """
}

workflow BIOC_CONSICA_CONSENSUS_ICA_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samples_data, Var, Sur ] ]

    main:
    BIOC_CONSICA_CONSENSUS_ICA_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_CONSICA_CONSENSUS_ICA_WORKFLOW.out.tables
    plots    = BIOC_CONSICA_CONSENSUS_ICA_WORKFLOW.out.plots
    objects  = BIOC_CONSICA_CONSENSUS_ICA_WORKFLOW.out.objects
    versions = BIOC_CONSICA_CONSENSUS_ICA_WORKFLOW.out.versions
}
