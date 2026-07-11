#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geNetClassifier — visualize_classifier_results
// Generate diagnostic and biological plots including ranked significant genes, gene expression profiles, discriminant power, and gene networks.
// Input: trained_classifier.RData, expression_data.RData
// Container: quay.io/biocontainers/bioconductor-genetclassifier:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, geNetClassifier
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot Ranked Significant Genes
//  * 2. [Visualization & Output] Plot Gene Expression Profiles
//  * 3. [Visualization & Output] Plot Genes Discriminant Power
//  * 4. [Visualization & Output] Plot Gene Networks

nextflow.enable.dsl = 2

process BIOC_GENETCLASSIFIER_VISUALIZE_CLASSIFIER_RESULTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("geNetClassifier", "Biobase")
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
    library(geNetClassifier)
    library(Biobase)
    
    # ==========================================
    # 1. LOAD USER INPUT FILES
    # ==========================================
    
    # Load trained classifier
    if (!file.exists("trained_classifier.RData")) {
      stop("Required input file 'trained_classifier.RData' not found in the working directory.")
    }
    env_classifier <- new.env()
    load("trained_classifier.RData", envir = env_classifier)
    obj_names <- ls(env_classifier)
    leukemiasClassifier <- NULL
    for (name in obj_names) {
      if (inherits(env_classifier[[name]], "GeNetClassifierReturn")) {
        leukemiasClassifier <- env_classifier[[name]]
        break
      }
    }
    if (is.null(leukemiasClassifier)) {
      stop("No GeNetClassifierReturn object found in 'trained_classifier.RData'.")
    }
    
    # Load expression data
    if (!file.exists("expression_data.RData")) {
      stop("Required input file 'expression_data.RData' not found in the working directory.")
    }
    env_eset <- new.env()
    load("expression_data.RData", envir = env_eset)
    obj_names_eset <- ls(env_eset)
    leukemiasEset <- NULL
    for (name in obj_names_eset) {
      if (inherits(env_eset[[name]], "ExpressionSet")) {
        leukemiasEset <- env_eset[[name]]
        break
      }
    }
    if (is.null(leukemiasEset)) {
      stop("No ExpressionSet object found in 'expression_data.RData'.")
    }
    
    # Dynamically find the column in pData that contains the class labels
    expected_classes <- names(numGenes(leukemiasClassifier@genesRanking))
    sample_labels_col <- NULL
    
    if (ncol(pData(leukemiasEset)) > 0) {
      for (col in colnames(pData(leukemiasEset))) {
        if (any(pData(leukemiasEset)[[col]] %in% expected_classes)) {
          sample_labels_col <- col
          break
        }
      }
    }
    
    # Fallback: predict classes if no suitable column is found
    if (is.null(sample_labels_col)) {
      queryResult <- queryGeNetClassifier(leukemiasClassifier, leukemiasEset, minProbAssignCoeff=0, minDiffAssignCoeff=0)
      leukemiasEset\$PredictedClass <- queryResult\$class
      sample_labels_col <- "PredictedClass"
    }
    
    # Define trainSamples dynamically based on the loaded ExpressionSet
    trainSamples <- seq_len(ncol(leukemiasEset))
    
    # Construct geneSymbols mapping dynamically from the ExpressionSet feature names
    geneSymbols <- featureNames(leukemiasEset)
    names(geneSymbols) <- featureNames(leukemiasEset)
    
    # Open PDF device to capture diagnostic plots
    pdf("geNetClassifier_diagnostic_plots.pdf", width = 10, height = 8)
    
    # ==========================================
    # --- Plot Ranked Significant Genes ---
    # ==========================================
    plot(leukemiasClassifier@genesRanking)
    plot(leukemiasClassifier@genesRanking, numGenesPlot=3000, lpThreshold=0.80)
    
    # ==========================================
    # --- Plot Gene Expression Profiles ---
    # ==========================================
    topGenes <- getRanking(getTopRanking(leukemiasClassifier@classificationGenes,numGenesClass=1), showGeneID=TRUE)\$geneID
    
    # Dynamically select up to the first two available classes for plotting
    available_classes <- colnames(topGenes)
    classes_to_plot <- available_classes[1:min(2, length(available_classes))]
    plotExpressionProfiles(leukemiasEset, topGenes[, classes_to_plot, drop=FALSE], sampleLabels=sample_labels_col, geneLabels=geneSymbols)
    
    # Plot expression profiles for train samples (writes to leukExprs_trainSamples.pdf)
    plotExpressionProfiles(leukemiasEset[,trainSamples], leukemiasClassifier, sampleLabels=sample_labels_col, fileName="leukExprs_trainSamples.pdf")
    
    # ==========================================
    # --- Plot Genes Discriminant Power ---
    # ==========================================
    # Dynamically select the first classification gene
    all_class_genes <- getRanking(leukemiasClassifier@classificationGenes, showGeneID=TRUE)\$geneID
    dynamic_gene <- na.omit(as.vector(all_class_genes))[1]
    
    if (!is.na(dynamic_gene)) {
      plotDiscriminantPower(leukemiasClassifier, classificationGenes=dynamic_gene)
    }
    
    # Dynamically select genes from the first available class for the discriminant power table
    first_class <- colnames(all_class_genes)[1]
    num_genes <- min(4, nrow(all_class_genes))
    discPowerTable <- plotDiscriminantPower(leukemiasClassifier, classificationGenes=all_class_genes[1:num_genes, first_class, drop=FALSE], returnTable=TRUE)
    
    # Save the discriminant power table
    write.csv(discPowerTable, "discriminant_power_table.csv", row.names = TRUE)
    
    # ==========================================
    # --- Plot Gene Networks ---
    # ==========================================
    clGenesSubNet <- getSubNetwork(leukemiasClassifier@genesNetwork, leukemiasClassifier@classificationGenes)
    clGenesInfo <- genesDetails(leukemiasClassifier@classificationGenes)
    
    # Dynamically plot the first available network
    if (length(clGenesSubNet) > 0) {
      plotNetwork(genesNetwork=clGenesSubNet[[1]], genesInfo=clGenesInfo)
    }
    
    # Close PDF device
    dev.off()
    
    # Save extracted network and gene details objects
    saveRDS(clGenesSubNet, "clGenesSubNet.rds")
    saveRDS(clGenesInfo, "clGenesInfo.rds")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_GENETCLASSIFIER_VISUALIZE_CLASSIFIER_RESULTS",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GENETCLASSIFIER_VISUALIZE_CLASSIFIER_RESULTS":',
        paste0('    geNetClassifier: ', as.character(packageVersion('geNetClassifier')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_visualize_classifier_results.csv versions.yml
    """
}

workflow BIOC_GENETCLASSIFIER_VISUALIZE_CLASSIFIER_RESULTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ trained_classifier.RData, expression_data.RData ] ]

    main:
    BIOC_GENETCLASSIFIER_VISUALIZE_CLASSIFIER_RESULTS(ch_input)

    emit:
    tables   = BIOC_GENETCLASSIFIER_VISUALIZE_CLASSIFIER_RESULTS.out.tables
    plots    = BIOC_GENETCLASSIFIER_VISUALIZE_CLASSIFIER_RESULTS.out.plots
    objects  = BIOC_GENETCLASSIFIER_VISUALIZE_CLASSIFIER_RESULTS.out.objects
    versions = BIOC_GENETCLASSIFIER_VISUALIZE_CLASSIFIER_RESULTS.out.versions
}
