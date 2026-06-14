#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: multistateQTL — multistate_qtl_analysis
// Analyze, preprocess, call significance, and visualize multi-state QTL summary statistics across different tissues or conditions.
// Input: input_df, qtl_summary_stats.tsv
// Container: quay.io/biocontainers/bioconductor-multistateqtl:2.2.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, QTLExperiment, multistateQTL
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load and format QTL summary statistics into a QTLExperiment object using sumstats2qtle
//  * 2. [Core Analysis] Estimate simulation parameters from the input data using qtleEstimate
//  * 3. [Core Analysis] Simulate multi-state QTL data using qtleSimulate
//  * 4. [Core Analysis] Filter out associations with high missingness using getComplete
//  * 5. [Core Analysis] Impute remaining missing values using replaceNAs
//  * 6. [Core Analysis] Call significance across states using single or two-step thresholds with callSignificance
//  * 7. [Core Analysis] Evaluate significance calling performance using simPerformance
//  * 8. [Core Analysis] Calculate pairwise sharing and identify top hits using getSignificant, getTopHits, and runPairwiseSharing
//  * 9. [Visualization & Output] Visualize global sharing patterns using plotPairwiseSharing and plotUpSet
//  * 10. [Visualization & Output] Categorize QTLs into global, multi-state, or unique types using runTestMetrics and visualize with plotCompareStates and plotQTLClu

nextflow.enable.dsl = 2

process BIOC_MULTISTATEQTL_MULTISTATE_QTL_ANALYSIS {
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
    .bm_deps <- c("QTLExperiment", "multistateQTL", "SummarizedExperiment")
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
    
    # Set seed for reproducibility
    set.seed(42)
    
    # Load required libraries
       library(SummarizedExperiment)
 library(QTLExperiment)
    library(multistateQTL)
    
    # ==========================================
    # 1. Load and Format QTL Summary Statistics
    # ==========================================
    
    # Find and read the input_df file
    input_file <- NULL
    for (f in c("input_df", "input_df.csv", "input_df.tsv", "input_df.txt")) {
        if (file.exists(f)) {
            input_file <- f
            break
        }
    }
    
    if (is.null(input_file)) {
        stop("Error: Could not find 'input_df' file in the working directory.")
    }
    
    # Read the input data frame
    if (grepl("\\\\.csv\$", input_file)) {
        input <- read.csv(input_file, stringsAsFactors=FALSE)
    } else {
        input <- read.delim(input_file, stringsAsFactors=FALSE)
    }
    
    # Ensure columns are named 'state' and 'path'
    if (!"state" %in% colnames(input) && "state_name" %in% colnames(input)) {
        colnames(input)[colnames(input) == "state_name"] <- "state"
    }
    if (!"path" %in% colnames(input) && "file_path" %in% colnames(input)) {
        colnames(input)[colnames(input) == "file_path"] <- "path"
    }
    if (!"state" %in% colnames(input)) colnames(input)[1] <- "state"
    if (!"path" %in% colnames(input)) colnames(input)[2] <- "path"
    
    # Verify and adjust paths if necessary
    for (i in seq_len(nrow(input))) {
        if (!file.exists(input\$path[i])) {
            base_name <- basename(input\$path[i])
            if (file.exists(base_name)) {
                input\$path[i] <- base_name
            } else if (file.exists("qtl_summary_stats.tsv")) {
                input\$path[i] <- "qtl_summary_stats.tsv"
            } else {
                stop(paste("Error: QTL summary statistics file not found for state:", input\$state[i]))
            }
        }
    }
    
    # Load summary statistics into a QTLExperiment object
    gtex <- sumstats2qtle(
        input, 
        feature_id="molecular_trait_id",
        variant_id="rsid", 
        betas="beta", 
        errors="se",
        pvalues="pvalue", 
        verbose=TRUE)
    
    # Save the loaded QTLExperiment object
    saveRDS(gtex, "gtex_qtle.rds")
    
    # ==========================================
    # 2. Estimate Simulation Parameters
    # ==========================================
    
    params <- qtleEstimate(gtex, threshSig=0.05, threshNull=0.5)
    saveRDS(params, "estimated_params.rds")
    
    # Visualize estimated simulation parameters
    pdf("simulation_params_plot.pdf", width=8, height=6)
    plotSimulationParams(params=params)
    dev.off()
    
    # ==========================================
    # 3. Simulate Multi-State QTL Data
    # ==========================================
    
    sim <- qtleSimulate(
        nStates=10, nFeatures=100, nTests=1000,
        global=0.2, multi=0.4, unique=0.2, k=2)
    
    saveRDS(sim, "simulated_qtl_raw.rds")
    
    # ==========================================
    # 4. Handle Missing Data (Filtering & Imputation)
    # ==========================================
    
    sim_na <- sim
    na_pattern <- sample(seq(1, ncol(sim)*nrow(sim)), 1000)
    assay(sim_na, "betas")[na_pattern] <- NA
    assay(sim_na, "errors")[na_pattern] <- NA
    assay(sim_na, "lfsrs")[na_pattern] <- NA
    
    # Filter out associations with high missingness
    sim_na <- getComplete(sim_na, n=0.5, verbose=TRUE)
    
    # Impute remaining missing values
    sim_na <- replaceNAs(sim_na, verbose=TRUE)
    saveRDS(sim_na, "simulated_qtl_imputed.rds")
    
    # ==========================================
    # 5. Call Significance & Evaluate Performance
    # ==========================================
    
    # Call significance using a flexible two-step threshold approach
    sim <- callSignificance(
        sim, mode="simple", assay="lfsrs",
        thresh=0.0001, secondThresh=0.0002)
    
    # Evaluate performance metrics
    perf_metrics <- simPerformance(sim)
    saveRDS(perf_metrics, "performance_metrics.rds")
    
    # Write performance metrics summary to a text file
    sink("performance_metrics_summary.txt")
    print(perf_metrics)
    sink()
    
    # ==========================================
    # 6. Calculate Pairwise Sharing & Top Hits
    # ==========================================
    
    sim_sig <- getSignificant(sim)
    sim_top <- getTopHits(sim_sig, assay="lfsrs", mode="state")
    sim_top <- runPairwiseSharing(sim_top)
    
    # Save top hits object
    saveRDS(sim_top, "sim_top.rds")
    
    # ==========================================
    # 7. Visualize Global Sharing Patterns
    # ==========================================
    
    # Plot pairwise sharing
    pdf("pairwise_sharing_plot.pdf", width=8, height=6)
    p1 <- plotPairwiseSharing(sim_top, annotateColsBy=c("nSignificant", "multistateGroup"))
    if (inherits(p1, "Heatmap") || inherits(p1, "HeatmapList")) {
        ComplexHeatmap::draw(p1)
    } else {
        print(p1)
    }
    dev.off()
    
    # Plot UpSet
    pdf("upset_plot.pdf", width=8, height=6)
    p_upset <- plotUpSet(sim_top, annotateColsBy=c("nSignificant", "multistateGroup"))
    if (inherits(p_upset, "Heatmap") || inherits(p_upset, "HeatmapList")) {
        ComplexHeatmap::draw(p_upset)
    } else {
        print(p_upset)
    }
    dev.off()
    
    # ==========================================
    # 8. Categorize and Visualize QTL Types
    # ==========================================
    
    sim_top <- runTestMetrics(sim_top)
    
    # Compare states S01 and S02
    pdf("compare_states_plot.pdf", width=8, height=6)
    pcs <- plotCompareStates(sim_top, x="S01", y="S02")
    print(pcs\$plot)
    dev.off()
    
    # Save state comparison counts
    write.csv(as.data.frame(pcs\$counts), "compare_states_counts.csv", row.names=TRUE)
    
    # Subset to multi-state QTLs and plot clusters
    sim_top_ms <- subset(sim_top, qtl_type_simple == "multistate")
    saveRDS(sim_top_ms, "sim_top_ms.rds")
    
    pdf("qtl_clusters_plot.pdf", width=8, height=6)
    p_clusters <- plotQTLClusters(
        sim_top_ms, 
        annotateColsBy=c("multistateGroup"),
        annotateRowsBy=c("qtl_type", "mean_beta", "QTL"))
    if (inherits(p_clusters, "Heatmap") || inherits(p_clusters, "HeatmapList")) {
        ComplexHeatmap::draw(p_clusters)
    } else {
        print(p_clusters)
    }
    dev.off()
    
    # Save session info
    writeLines(capture.output(sessionInfo()), "session_info.txt")

    writeLines(c(
        '"BIOC_MULTISTATEQTL_MULTISTATE_QTL_ANALYSIS":',
        paste0('    multistateQTL: ', as.character(packageVersion('multistateQTL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multistate_qtl_analysis.csv versions.yml
    """
}

workflow BIOC_MULTISTATEQTL_MULTISTATE_QTL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input_df, qtl_summary_stats.tsv ] ]

    main:
    BIOC_MULTISTATEQTL_MULTISTATE_QTL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MULTISTATEQTL_MULTISTATE_QTL_ANALYSIS.out.tables
    plots    = BIOC_MULTISTATEQTL_MULTISTATE_QTL_ANALYSIS.out.plots
    objects  = BIOC_MULTISTATEQTL_MULTISTATE_QTL_ANALYSIS.out.objects
    versions = BIOC_MULTISTATEQTL_MULTISTATE_QTL_ANALYSIS.out.versions
}
