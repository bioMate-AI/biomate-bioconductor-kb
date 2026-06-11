#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: proloc — nearest_neighbour_transfer_learning
// Combine primary experimental spatial proteomics data with auxiliary data (e.g., GO terms) using weighted k-nearest neighbour transfer learning to predict sub-ce
// Input: primary_data.csv, auxiliary_data.csv
// Container: quay.io/biocontainers/bioconductor-proloc:1.50.0--r45ha27e39d_0
// R packages: MSnbase, pRoloc
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROLOC_NEAREST_NEIGHBOUR_TRANSFER_LEARNING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-proloc:1.50.0--r45ha27e39d_0"

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
    .bm_deps <- c("MSnbase", "pRoloc")
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
    library(MSnbase)
    library(pRoloc)
    
    # 1. Read primary and auxiliary data from the working directory
    if (!file.exists("primary_data.csv")) {
      stop("Error: 'primary_data.csv' not found in the working directory.")
    }
    if (!file.exists("auxiliary_data.csv")) {
      stop("Error: 'auxiliary_data.csv' not found in the working directory.")
    }
    
    primary_df <- read.csv("primary_data.csv", row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
    aux_df <- read.csv("auxiliary_data.csv", row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
    
    # Ensure markers.tl column exists in primary data
    if (!"markers.tl" %in% colnames(primary_df)) {
      if ("markers" %in% colnames(primary_df)) {
        primary_df\$markers.tl <- primary_df\$markers
      } else {
        stop("Error: primary_data.csv must contain a 'markers.tl' or 'markers' column.")
      }
    }
    
    # Clean marker annotations: treat empty strings or NA as "unknown"
    markers <- as.character(primary_df\$markers.tl)
    markers[is.na(markers) | markers == "" | tolower(markers) == "unknown"] <- "unknown"
    primary_df\$markers.tl <- markers
    
    # Separate quantitative columns (numeric) from feature metadata
    numeric_cols <- sapply(primary_df, is.numeric)
    numeric_cols["markers.tl"] <- FALSE  # Ensure markers.tl is treated as feature metadata
    
    exprs_primary <- as.matrix(primary_df[, numeric_cols, drop = FALSE])
    fdata_primary <- primary_df[, !numeric_cols, drop = FALSE]
    
    # Construct primary MSnSet
    andy2011 <- MSnSet(exprs = exprs_primary, fData = fdata_primary)
    
    # Align proteins between primary and auxiliary datasets
    common_proteins <- intersect(rownames(andy2011), rownames(aux_df))
    if (length(common_proteins) == 0) {
      stop("Error: No common protein identifiers found between primary_data.csv and auxiliary_data.csv.")
    }
    
    andy2011 <- andy2011[common_proteins, ]
    aux_df_matched <- aux_df[common_proteins, , drop = FALSE]
    
    # Separate quantitative columns for auxiliary data
    numeric_aux_cols <- sapply(aux_df_matched, is.numeric)
    exprs_aux <- as.matrix(aux_df_matched[, numeric_aux_cols, drop = FALSE])
    
    # Construct auxiliary MSnSet (must share feature names and metadata with primary)
    andy2011goCC <- MSnSet(exprs = exprs_aux, fData = fData(andy2011))
    
    # Define marker classes excluding "unknown"
    m <- unique(fData(andy2011)\$markers.tl)
    m <- m[m != "unknown"]
    
    # 2. Define weight combinations using thetas
    th <- thetas(length(m), length.out=4)
    
    # 3. Optimize class-specific weights using knntlOptimisation
    topt <- knntlOptimisation(andy2011, andy2011goCC, th = th, k = c(3, 3), fcol = "markers.tl", times = 50)
    
    # 4. Extract the best parameters using getParams
    bw <- getParams(topt)
    getParams(topt)
    
    # 5. Apply the optimal weights and classify unlabelled proteins using knntlClassification
    andy2011 <- knntlClassification(andy2011, andy2011goCC, bestTheta = bw, k = c(3, 3), fcol = "markers.tl")
    
    # 6. Extract predictions and scores using getPredictions
    andy2011 <- getPredictions(andy2011, fcol = "knntl")
    
    # 7. Write named output files for the results
    # Save predictions and scores to CSV
    predictions_df <- data.frame(
      Protein = rownames(fData(andy2011)),
      Prediction = fData(andy2011)\$knntl,
      Score = fData(andy2011)\$knntl.scores,
      stringsAsFactors = FALSE
    )
    write.csv(predictions_df, "predictions.csv", row.names = FALSE)
    
    # Save RDS objects
    saveRDS(topt, "topt_parameters.rds")
    saveRDS(andy2011, "classification_results.rds")
    
    # Save PCA plot of the classification results
    pdf("pca_plot.pdf", width = 8, height = 8)
    setStockcol(paste0(getStockcol(), "80"))
    ptsze <- exp(fData(andy2011)\$knntl.scores) - 1
    plot2D(andy2011, fcol = "knntl", cex = ptsze)
    setStockcol(NULL)
    addLegend(andy2011, where = "topright", fcol = "markers.tl", bty = "n", cex = .7)
    dev.off()

    writeLines(c(
        '"BIOC_PROLOC_NEAREST_NEIGHBOUR_TRANSFER_LEARNING":',
        paste0('        proloc: ', as.character(packageVersion("proloc")))
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
