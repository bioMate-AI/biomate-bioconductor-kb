#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BUScorrect — bus_correct_list_input
// Correct batch effects and identify unknown subtypes from an R list of gene expression matrices using the BUS model.
// Input: list_of_matrices.rds
// Container: quay.io/biocontainers/bioconductor-buscorrect:1.28.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BUScorrect
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the BUS model using Gibbs sampling with BUSgibbs
//  * 2. [Core Analysis] Extract estimated subtypes using Subtypes
//  * 3. [Core Analysis] Extract location and scale batch effects using location_batch_effects and scale_batch_effects
//  * 4. [Core Analysis] Extract subtype effects using subtype_effects
//  * 5. [Core Analysis] Identify intrinsic genes using postprob_DE_thr_fun, estimate_IG_indicators, and IG_index
//  * 6. [Core Analysis] Calculate posterior probabilities of differential expression using postprob_DE
//  * 7. [Core Analysis] Obtain batch-corrected expression values using adjusted_values
//  * 8. [Visualization & Output] Visualize original and adjusted data using visualize_data
//  * 9. [Core Analysis] Perform model selection for subtype number using BIC_BUS

nextflow.enable.dsl = 2

process BIOC_BUSCORRECT_BUS_CORRECT_LIST_INPUT {
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
    .bm_deps <- c("BUScorrect")
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
    
    # Load the required Bioconductor package
    library(BUScorrect)
    
    # Read the user-provided list of gene expression matrices
    if (!file.exists("list_of_matrices.rds")) {
      stop("Error: Input file 'list_of_matrices.rds' not found in the working directory.")
    }
    BUSexample_data <- readRDS("list_of_matrices.rds")
    
    # 1. Model Fitting using Gibbs sampling
    set.seed(123)
    BUSfits <- BUSgibbs(Data = BUSexample_data, n.subtypes = 3, n.iterations = 300, 
    						showIteration = FALSE)
    
    # Save the fitted model object
    saveRDS(BUSfits, "BUSfits_k3.rds")
    
    # Capture and save the summary of the model fit
    sink("BUSfits_summary.txt")
    summary(BUSfits)
    sink()
    
    # 2. Extract Estimated Subtypes
    est_subtypes <- Subtypes(BUSfits)
    saveRDS(est_subtypes, "estimated_subtypes.rds")
    
    # 3. Extract Location and Scale Batch Effects
    est_location_batch_effects <- location_batch_effects(BUSfits)
    write.csv(est_location_batch_effects, "location_batch_effects.csv", row.names = FALSE)
    
    est_scale_batch_effects <- scale_batch_effects(BUSfits)
    write.csv(est_scale_batch_effects, "scale_batch_effects.csv", row.names = FALSE)
    
    # 4. Extract Subtype Effects
    est_subtype_effects <- subtype_effects(BUSfits)
    write.csv(est_subtype_effects, "subtype_effects.csv", row.names = FALSE)
    
    # 5. Identify Intrinsic Genes
    thr0 <- postprob_DE_thr_fun(BUSfits, fdr_threshold=0.01)
    est_L <- estimate_IG_indicators(BUSfits, postprob_DE_threshold=thr0)
    intrinsic_gene_indices <- IG_index(est_L)
    write.csv(data.frame(IntrinsicGeneIndex = intrinsic_gene_indices), "intrinsic_gene_indices.csv", row.names = FALSE)
    
    # 6. Calculate Posterior Probabilities of Differential Expression
    postprob_DE_matr <- postprob_DE(BUSfits)
    write.csv(postprob_DE_matr, "postprob_DE.csv", row.names = FALSE)
    
    # 7. Obtain Batch-Corrected Expression Values
    adjusted_data <- adjusted_values(BUSfits, BUSexample_data)
    saveRDS(adjusted_data, "adjusted_data.rds")
    
    # 8. Visualize Original and Adjusted Data
    pdf("expression_heatmaps.pdf", width = 8, height = 8)
    visualize_data(BUSexample_data, title_name = "original expression values", 
    								gene_ind_set = 1:100) 
    visualize_data(adjusted_data, title_name = "adjusted expression values", 
    								gene_ind_set = 1:100) 
    dev.off()
    
    # 9. Perform Model Selection using BIC
    BIC_val <- BIC_BUS(BUSfits)
    writeLines(as.character(BIC_val), "BIC_val_k3.txt")
    
    BIC_values <- NULL
    for(k in 2:4){
    	set.seed(123)
    	BUSfits <- BUSgibbs(Data = BUSexample_data, n.subtypes = k, n.iterations = 300, 
    						showIteration = FALSE)
    	BIC_values <- c(BIC_values, BIC_BUS(BUSfits))
    }
    
    # Save the BIC values for different subtype numbers
    write.csv(data.frame(SubtypeNumber = 2:4, BIC = BIC_values), "BIC_values_k2_to_k4.csv", row.names = FALSE)
    
    # Plot and save the BIC curve
    pdf("bic_plot.pdf", width = 6, height = 6)
    plot(2:4, BIC_values, xlab="subtype number", ylab="BIC", main="BIC plot", type="b")
    dev.off()

    writeLines(c(
        '"BIOC_BUSCORRECT_BUS_CORRECT_LIST_INPUT":',
        paste0('    BUScorrect: ', as.character(packageVersion('BUScorrect')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bus_correct_list_input.csv versions.yml
    """
}

workflow BIOC_BUSCORRECT_BUS_CORRECT_LIST_INPUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ list_of_matrices.rds ] ]

    main:
    BIOC_BUSCORRECT_BUS_CORRECT_LIST_INPUT(ch_input)

    emit:
    tables   = BIOC_BUSCORRECT_BUS_CORRECT_LIST_INPUT.out.tables
    plots    = BIOC_BUSCORRECT_BUS_CORRECT_LIST_INPUT.out.plots
    objects  = BIOC_BUSCORRECT_BUS_CORRECT_LIST_INPUT.out.objects
    versions = BIOC_BUSCORRECT_BUS_CORRECT_LIST_INPUT.out.versions
}
