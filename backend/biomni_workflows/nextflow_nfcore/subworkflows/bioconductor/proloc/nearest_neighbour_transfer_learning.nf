#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pRoloc — nearest_neighbour_transfer_learning
// Combine primary experimental spatial proteomics data with auxiliary annotation data (such as Gene Ontology terms) using a weighted k-nearest neighbor transfer l
// Input: primary_data.csv, auxiliary_data.csv
// Container: quay.io/biocontainers/bioconductor-proloc:1.50.0--r45ha27e39d_0
// Requires: BiocParallel, MSnbase, pRoloc
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the primary and auxiliary MSnSet objects, ensuring they contain the same features in the same order. 2. Generate a matrix of 

nextflow.enable.dsl = 2

process BIOC_PROLOC_NEAREST_NEIGHBOUR_TRANSFER_LEARNING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
            
    # Load required libraries
    library(pRoloc)
    library(MSnbase)
    library(BiocParallel)
    
    # Check if input files exist
    if (!file.exists("primary_data.csv") || !file.exists("auxiliary_data.csv")) {
      stop("Required input files 'primary_data.csv' and/or 'auxiliary_data.csv' are missing.")
    }
    
    # 1. Load the primary and auxiliary MSnSet objects, ensuring they contain the same features in the same order.
    primary_df <- read.csv("primary_data.csv", row.names = 1, check.names = FALSE)
    fcol <- "markers.tl"
    
    if (!fcol %in% colnames(primary_df)) {
      if ("markers" %in% colnames(primary_df)) {
        colnames(primary_df)[colnames(primary_df) == "markers"] <- fcol
      } else {
        stop("primary_data.csv must contain a 'markers.tl' or 'markers' column.")
      }
    }
    
    # Separate expression and feature data
    # Use is.numeric to identify continuous expression data and exclude integer metadata columns
    exprs_cols <- sapply(primary_df, is.numeric)
    exprs_cols[fcol] <- FALSE
    
    exprs_mat <- as.matrix(primary_df[, exprs_cols, drop = FALSE])
    fdata_df <- primary_df[, !exprs_cols, drop = FALSE]
    
    # Ensure markers.tl is character and has "unknown" for missing values
    fdata_df[[fcol]] <- as.character(fdata_df[[fcol]])
    fdata_df[[fcol]][is.na(fdata_df[[fcol]]) | fdata_df[[fcol]] == ""] <- "unknown"
    
    primary_msnset <- MSnSet(exprs = exprs_mat, fData = fdata_df)
    
    # Read auxiliary data
    auxiliary_df <- read.csv("auxiliary_data.csv", row.names = 1, check.names = FALSE)
    aux_exprs <- as.matrix(auxiliary_df)
    
    # Align features
    common_features <- intersect(featureNames(primary_msnset), rownames(aux_exprs))
    if (length(common_features) == 0) {
      stop("No common features (proteins) found between primary and auxiliary data.")
    }
    primary_msnset <- primary_msnset[common_features, ]
    aux_exprs <- aux_exprs[common_features, , drop = FALSE]
    
    # Construct auxiliary MSnSet
    auxiliary_msnset <- MSnSet(exprs = aux_exprs, fData = fData(primary_msnset))
    
    # 2. Generate a matrix of candidate class-specific weights using thetas.
    m <- unique(fData(primary_msnset)\$markers.tl)
    m <- m[m != "unknown"]
    if (length(m) == 0) {
      stop("No marker classes found in 'markers.tl' column (excluding 'unknown').")
    }
    
    th <- thetas(length(m), length.out=3)
    
    # 3. Optimize the class-specific weights using knntlOptimisation with parallel execution support.
    set.seed(1)
    
    topt <- knntlOptimisation(primary_msnset, auxiliary_msnset, th = th, k = c(3, 3), fcol = "markers.tl", times = 50, BPPARAM = BiocParallel::bpparam())
    
    # 4. Extract the optimized weight parameters using getParams.
    bw <- getParams(topt)
    
    # 5. Apply the optimized weights to classify unlabelled proteins using knntlClassification.
    primary_msnset <- knntlClassification(primary_msnset, auxiliary_msnset, bestTheta = bw, k = c(3, 3), fcol = "markers.tl")
    
    # 6. Retrieve the final localization predictions and classification scores using getPredictions.
    primary_msnset <- getPredictions(primary_msnset, fcol = "knntl", mcol = "markers.tl")
    
    # Write named output files
    saveRDS(topt, "optimized_weights.rds")
    saveRDS(primary_msnset, "classified_proteins.rds")
    
    # Extract predictions and scores to CSV
    results_df <- data.frame(
      Protein = featureNames(primary_msnset),
      Primary_Markers = fData(primary_msnset)\$markers.tl,
      Predicted_Localisation = fData(primary_msnset)\$knntl,
      Classification_Score = fData(primary_msnset)\$knntl.scores,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "predictions.csv", row.names = FALSE)
    
    # Save PDF plot
    pdf("classification_plot.pdf", width = 8, height = 6)
    setStockcol(paste0(getStockcol(), "80"))
    ptsze <- exp(fData(primary_msnset)\$knntl.scores) - 1
    plot2D(primary_msnset, fcol = "knntl", cex = ptsze)
    setStockcol(NULL)
    addLegend(primary_msnset, where = "topright", fcol = "markers.tl", bty = "n", cex = .7)
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'optimized_weights.rds', 'classified_proteins.rds', 'predictions.csv', and 'classification_plot.pdf'.")

    writeLines(c(
        '"BIOC_PROLOC_NEAREST_NEIGHBOUR_TRANSFER_LEARNING":',
        paste0('    pRoloc: ', as.character(packageVersion('pRoloc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nearest_neighbour_transfer_learning.csv versions.yml
    """
}

workflow BIOC_PROLOC_NEAREST_NEIGHBOUR_TRANSFER_LEARNING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ primary_data.csv, auxiliary_data.csv ] ]

    main:
    BIOC_PROLOC_NEAREST_NEIGHBOUR_TRANSFER_LEARNING(ch_input)

    emit:
    tables   = BIOC_PROLOC_NEAREST_NEIGHBOUR_TRANSFER_LEARNING.out.tables
    plots    = BIOC_PROLOC_NEAREST_NEIGHBOUR_TRANSFER_LEARNING.out.plots
    objects  = BIOC_PROLOC_NEAREST_NEIGHBOUR_TRANSFER_LEARNING.out.objects
    versions = BIOC_PROLOC_NEAREST_NEIGHBOUR_TRANSFER_LEARNING.out.versions
}
