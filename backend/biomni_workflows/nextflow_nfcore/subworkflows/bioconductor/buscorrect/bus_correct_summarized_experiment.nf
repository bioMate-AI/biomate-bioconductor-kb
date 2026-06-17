#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BUScorrect — bus_correct_summarized_experiment
// Correct batch effects and identify unknown subtypes from a SummarizedExperiment object.
// Input: summarized_experiment.rds
// Container: quay.io/biocontainers/bioconductor-buscorrect:1.28.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BUScorrect, SummarizedExperiment
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load SummarizedExperiment and prepare the object
//  * 2. [Visualization & Output] Fit the BUS model using BUSgibbs with the SummarizedExperiment object
//  * 3. [Core Analysis] Extract estimated subtypes using Subtypes

nextflow.enable.dsl = 2

process BIOC_BUSCORRECT_BUS_CORRECT_SUMMARIZED_EXPERIMENT {
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
    .bm_deps <- c("BUScorrect", "SummarizedExperiment")
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
    library(BUScorrect)
    library(SummarizedExperiment)
    
    # 1. Load SummarizedExperiment and prepare the object
    # Read the user-provided SummarizedExperiment object
    BUSdata_SumExp <- readRDS("summarized_experiment.rds")
    
    # 2. Fit the BUS model using BUSgibbs with the SummarizedExperiment object
    set.seed(123)
    BUSfits_SumExp <- BUSgibbs(Data = BUSdata_SumExp, n.subtypes = 3, n.iterations = 300, 
                               showIteration = FALSE)
    
    # Save the summary output to a text file
    sink("summary_output.txt")
    summary(BUSfits_SumExp)
    sink()
    
    # 3. Extract estimated subtypes using Subtypes
    est_subtypes <- Subtypes(BUSfits_SumExp)
    saveRDS(est_subtypes, "estimated_subtypes.rds")
    
    # Extract location and scale batch effects
    est_location_batch_effects <- location_batch_effects(BUSfits_SumExp)
    est_scale_batch_effects <- scale_batch_effects(BUSfits_SumExp)
    write.csv(est_location_batch_effects, "location_batch_effects.csv", row.names = FALSE)
    write.csv(est_scale_batch_effects, "scale_batch_effects.csv", row.names = FALSE)
    
    # Extract subtype effects
    est_subtype_effects <- subtype_effects(BUSfits_SumExp)
    write.csv(est_subtype_effects, "subtype_effects.csv", row.names = FALSE)
    
    # Identify intrinsic genes
    thr0 <- postprob_DE_thr_fun(BUSfits_SumExp, fdr_threshold=0.01)
    est_L <- estimate_IG_indicators(BUSfits_SumExp, postprob_DE_threshold=thr0)
    intrinsic_gene_indices <- IG_index(est_L)
    write.csv(data.frame(Intrinsic_Gene_Index = intrinsic_gene_indices), "intrinsic_genes.csv", row.names = FALSE)
    
    # Extract posterior probability matrix
    postprob_DE_matr <- postprob_DE(BUSfits_SumExp)
    write.csv(postprob_DE_matr, "posterior_probability_DE.csv", row.names = FALSE)
    
    # Prepare list format of original data for adjusted_values and visualization
    ge_matrix <- assays(BUSdata_SumExp)\$GE_matr
    batch_vec <- colData(BUSdata_SumExp)\$Batch
    unique_batches <- sort(unique(batch_vec))
    original_data_list <- lapply(unique_batches, function(b) {
      ge_matrix[, batch_vec == b, drop = FALSE]
    })
    
    # Obtain adjusted values
    adjusted_data <- adjusted_values(BUSfits_SumExp, original_data_list)
    saveRDS(adjusted_data, "adjusted_data_list.rds")
    
    # Generate visualization heatmaps
    pdf("expression_heatmaps.pdf", width = 10, height = 8)
    n_genes <- min(100, nrow(ge_matrix))
    visualize_data(original_data_list, title_name = "original expression values", 
                   gene_ind_set = 1:n_genes) 
    visualize_data(adjusted_data, title_name = "adjusted expression values", 
                   gene_ind_set = 1:n_genes) 
    dev.off()
    
    # Save the final model fit object
    saveRDS(BUSfits_SumExp, "BUSfits_SumExp.rds")

    writeLines(c(
        '"BIOC_BUSCORRECT_BUS_CORRECT_SUMMARIZED_EXPERIMENT":',
        paste0('    BUScorrect: ', as.character(packageVersion('BUScorrect')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bus_correct_summarized_experiment.csv versions.yml
    """
}

workflow BIOC_BUSCORRECT_BUS_CORRECT_SUMMARIZED_EXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ summarized_experiment.rds ] ]

    main:
    BIOC_BUSCORRECT_BUS_CORRECT_SUMMARIZED_EXPERIMENT(ch_input)

    emit:
    tables   = BIOC_BUSCORRECT_BUS_CORRECT_SUMMARIZED_EXPERIMENT.out.tables
    plots    = BIOC_BUSCORRECT_BUS_CORRECT_SUMMARIZED_EXPERIMENT.out.plots
    objects  = BIOC_BUSCORRECT_BUS_CORRECT_SUMMARIZED_EXPERIMENT.out.objects
    versions = BIOC_BUSCORRECT_BUS_CORRECT_SUMMARIZED_EXPERIMENT.out.versions
}
