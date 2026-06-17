#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: omada — modular_step_by_step_clustering
// Manually execute the step-by-step modular pipeline to analyze dataset feasibility, select the best clustering method, perform feature selection, vote on the opt
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-omada:1.12.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: omada
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Assess dataset feasibility based on dimensions or existing data statistics using feasibilityAnalysis or feasibilityAnalysisDataBas
//  * 2. [Core Analysis] Select the most appropriate clustering method using clusteringMethodSelection or compare specific algorithms using partitionAgreem
//  * 3. [Core Analysis] Select the most stable feature subset using featureSelection
//  * 4. [Core Analysis] Estimate the optimal number of clusters using clusterVoting
//  * 5. [Core Analysis] Execute the final partitioning using optimalClustering

nextflow.enable.dsl = 2

process BIOC_OMADA_MODULAR_STEP_BY_STEP_CLUSTERING {
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
    .bm_deps <- c("omada")
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
    
    # Load required library
    library(omada)
    
    # Read user input file
    toy_genes <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    toy_genes <- na.omit(toy_genes)
    toy_genes <- as.data.frame(toy_genes)
    
    # 1. Assess dataset feasibility based on dimensions or existing data statistics
    new.dataset.analysis <- feasibilityAnalysis(classes = 4, samples = 50, 
                                                features = 15)
    existing.dataset.analysis <- feasibilityAnalysisDataBased(data = toy_genes, 
                                                              classes = 3)
    average.sts.k <- get_average_stabilities_per_k(new.dataset.analysis)
    maximum.st <- get_max_stability(new.dataset.analysis)
    average.st <- get_average_stability(new.dataset.analysis)
    generated.ds <- get_generated_dataset(new.dataset.analysis)
    
    # Save feasibility results
    write.csv(as.data.frame(average.sts.k), "average_stabilities_per_k.csv", row.names = TRUE)
    writeLines(as.character(maximum.st), "maximum_stability.txt")
    writeLines(as.character(average.st), "average_stability.txt")
    write.csv(as.data.frame(generated.ds), "generated_dataset.csv", row.names = TRUE)
    
    # 2. Select the most appropriate clustering method
    method.results <- clusteringMethodSelection(toy_genes, method.upper.k = 3, 
                                                number.of.comparisons = 2)
    pa.scores <- get_partition_agreement_scores(method.results)
    
    # Save partition agreement plot
    pdf("partition_agreement_plot.pdf")
    plot_partition_agreement(method.results)
    dev.off()
    
    # Save partition agreement scores
    write.csv(as.data.frame(pa.scores), "partition_agreement_scores.csv", row.names = TRUE)
    
    # Compare specific algorithms using partitionAgreement
    agreement.results <- partitionAgreement(toy_genes, algorithm.1 = "spectral", 
                                            measure.1 = "rbfdot", 
                                            algorithm.2 = "kmeans",
                                            measure.2 = "Lloyd", 
                                            number.of.clusters = 3)
    pa.scores_agreement <- get_agreement_scores(agreement.results)
    
    # Save agreement results
    saveRDS(agreement.results, "agreement_results.rds")
    write.csv(as.data.frame(pa.scores_agreement), "agreement_scores.csv", row.names = TRUE)
    
    # 3. Select the most stable feature subset
    feature.selection.results <-  featureSelection(toy_genes, min.k = 3, max.k = 6,
                                                   step = 3)
    feature.selection.scores <- get_average_feature_k_stabilities(feature.selection.results)
    optimal.number.of.features <- get_optimal_number_of_features(feature.selection.results)
    optimal.features <- get_optimal_features(feature.selection.results)
    
    # Save average stabilities plot
    pdf("average_stabilities_plot.pdf")
    plot_average_stabilities(feature.selection.results)
    dev.off()
    
    # Save feature selection results
    write.csv(as.data.frame(feature.selection.scores), "feature_selection_scores.csv", row.names = TRUE)
    writeLines(as.character(optimal.number.of.features), "optimal_number_of_features.txt")
    writeLines(optimal.features, "optimal_features.txt")
    
    # 4. Estimate the optimal number of clusters
    cluster.voting.results <- clusterVoting(toy_genes, 4, 8, "sc")
    internal.metric.scores <- get_internal_metric_scores(cluster.voting.results)
    cluster.memberships.k <- get_cluster_memberships_k(cluster.voting.results)
    metric.votes.k <- get_metric_votes_k(cluster.voting.results)
    vote.frequencies.k <- get_vote_frequencies_k(cluster.voting.results)
    
    # Save vote frequencies plot
    pdf("vote_frequencies_plot.pdf")
    plot_vote_frequencies(cluster.voting.results)
    dev.off()
    
    # Save cluster voting results
    write.csv(as.data.frame(internal.metric.scores), "internal_metric_scores.csv", row.names = TRUE)
    saveRDS(cluster.memberships.k, "cluster_memberships_k.rds")
    write.csv(as.data.frame(metric.votes.k), "metric_votes_k.csv", row.names = TRUE)
    write.csv(as.data.frame(vote.frequencies.k), "vote_frequencies_k.csv", row.names = TRUE)
    
    # 5. Execute the final partitioning
    sample.memberships <- optimalClustering(toy_genes, 4, "spectral")
    memberships <- get_optimal_memberships(sample.memberships)
    optimal.stability <- get_optimal_stability_score(sample.memberships)
    optimal.parameter <- get_optimal_parameter_used(sample.memberships)
    
    # Save final clustering results
    write.csv(as.data.frame(memberships), "optimal_memberships.csv", row.names = TRUE)
    writeLines(as.character(optimal.stability), "optimal_stability.txt")
    writeLines(as.character(optimal.parameter), "optimal_parameter.txt")

    writeLines(c(
        '"BIOC_OMADA_MODULAR_STEP_BY_STEP_CLUSTERING":',
        paste0('    omada: ', as.character(packageVersion('omada')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_modular_step_by_step_clustering.csv versions.yml
    """
}

workflow BIOC_OMADA_MODULAR_STEP_BY_STEP_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_OMADA_MODULAR_STEP_BY_STEP_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_OMADA_MODULAR_STEP_BY_STEP_CLUSTERING.out.tables
    plots    = BIOC_OMADA_MODULAR_STEP_BY_STEP_CLUSTERING.out.plots
    objects  = BIOC_OMADA_MODULAR_STEP_BY_STEP_CLUSTERING.out.objects
    versions = BIOC_OMADA_MODULAR_STEP_BY_STEP_CLUSTERING.out.versions
}
