#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: causalr — standard_causal_reasoning
// Predict, score, and rank upstream regulators at a specific path length (delta) and calculate their statistical significance.
// Input: testNetwork1.sif, testData1.txt
// Container: quay.io/biocontainers/bioconductor-causalr:1.42.0--r45hdfd78af_0
// R packages: CausalR, igraph
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_CAUSALR_STANDARD_CAUSAL_REASONING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-causalr:1.42.0--r45hdfd78af_0"

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
    .bm_deps <- c("CausalR", "igraph")
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
    library(CausalR)
    library(igraph)
    
    # --- Load the network and construct a Computational Causal ---
    # Reading from the user-provided 'testNetwork1.sif' in the working directory
    ccg <- CreateCCG("testNetwork1.sif")
    
    # Optional: Plot and save the CCG structure to a PDF file
    pdf("ccg_plot.pdf", width=10, height=10)
    PlotGraphWithNodeNames(ccg)
    dev.off()
    
    # --- Load the experimental data and map it to the CCG ---
    # Reading from the user-provided 'testData1.txt' in the working directory
    experimentalData <- ReadExperimentalData("testData1.txt", ccg)
    
    # --- Rank all hypotheses at a specific path length (delta=2) ---
    ranked_hypotheses <- RankTheHypotheses(ccg, experimentalData, delta=2)
    write.csv(ranked_hypotheses, "ranked_hypotheses_delta2.csv", row.names=FALSE)
    
    # --- Generate predictions for a specific signed hypothesis ---
    predictions <- MakePredictionsFromCCG('Node0', +1, ccg, 2)
    write.csv(predictions, "predictions_node0_plus.csv", row.names=FALSE)
    
    # Score the hypothesis predictions
    initial_score <- ScoreHypothesis(predictions, experimentalData)
    
    # Compare predictions with experimental data and map back to node names
    comparison <- GetNodeName(ccg, CompareHypothesis(predictions, experimentalData))
    write.csv(comparison, "comparison_node0_plus.csv", row.names=FALSE)
    
    # Re-calculate/assign Score for significance testing
    Score <- ScoreHypothesis(predictions, experimentalData)
    
    # --- Calculate exact and approximate significance p-values and ---
    # Calculate exact significance (quartic algorithm)
    sig_exact <- CalculateSignificance(Score, predictions, experimentalData)
    
    # Get experimental data statistics for the cubic approximation algorithm
    PreexperimentalDataStats <- GetNumberOfPositiveAndNegativeEntries(experimentalData)
    experimentalDataStats <- c(PreexperimentalDataStats, 1)
    
    # Analyse predictions list to get prediction statistics
    predictionListStats <- AnalysePredictionsList(predictions, 8)
    
    # Calculate approximate significance using the fast cubic algorithm
    sig_cubic <- CalculateSignificance(Score, predictionListStats, experimentalDataStats, useCubicAlgorithm=TRUE)
    
    # Calculate enrichment p-value
    enrichment_p <- CalculateEnrichmentPvalue(predictions, experimentalData)
    
    # Save all significance and scoring metrics to an RDS file
    significance_results <- list(
      Score = Score,
      ExactSignificancePValue = sig_exact,
      PreexperimentalDataStats = PreexperimentalDataStats,
      ExperimentalDataStats = experimentalDataStats,
      PredictionListStats = predictionListStats,
      CubicSignificancePValue = sig_cubic,
      EnrichmentPValue = enrichment_p
    )
    saveRDS(significance_results, "significance_results.rds")
    
    # --- Export the sub-network of correctly explained nodes for a ---
    # This will generate .sif and annotation files in the working directory
    WriteExplainedNodesToSifFile("Node1", +1, ccg, experimentalData, delta=2)

    writeLines(c(
        '"BIOC_CAUSALR_STANDARD_CAUSAL_REASONING":',
        paste0('        causalr: ', as.character(packageVersion("causalr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_causal_reasoning.csv versions.yml
    """
}

workflow BIOC_CAUSALR_STANDARD_CAUSAL_REASONING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ testNetwork1.sif, testData1.txt ] ]

    main:
    BIOC_CAUSALR_STANDARD_CAUSAL_REASONING(ch_input)

    emit:
    tables   = BIOC_CAUSALR_STANDARD_CAUSAL_REASONING.out.tables
    plots    = BIOC_CAUSALR_STANDARD_CAUSAL_REASONING.out.plots
    objects  = BIOC_CAUSALR_STANDARD_CAUSAL_REASONING.out.objects
    versions = BIOC_CAUSALR_STANDARD_CAUSAL_REASONING.out.versions
}
