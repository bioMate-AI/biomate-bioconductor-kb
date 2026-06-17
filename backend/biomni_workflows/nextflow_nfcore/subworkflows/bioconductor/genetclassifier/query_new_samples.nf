#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geNetClassifier — query_new_samples
// Classify new independent samples of known or unknown class using a pre-trained geNetClassifier model and evaluate prediction accuracy.
// Input: trained_classifier.RData, query_expression_data.RData
// Container: quay.io/biocontainers/bioconductor-genetclassifier:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, geNetClassifier
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load Inputs
//  * 2. [Visualization & Output] Run queryGeNetClassifier()
//  * 3. [Visualization & Output] Perform External Validation (if labels exist)
//  * 4. [Visualization & Output] Adjust Assignment Stringency Thresholds
//  * 5. [Visualization & Output] Summarize Query Results
//  * 6. [Visualization & Output] Write Outputs

nextflow.enable.dsl = 2

process BIOC_GENETCLASSIFIER_QUERY_NEW_SAMPLES {
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
    # --- Load Inputs ---
    # ==========================================
    
    if (!file.exists("trained_classifier.RData")) {
        stop("Error: trained_classifier.RData not found in the working directory.")
    }
    if (!file.exists("query_expression_data.RData")) {
        stop("Error: query_expression_data.RData not found in the working directory.")
    }
    
    # Load trained classifier dynamically to handle any object name
    env_classifier <- new.env()
    load("trained_classifier.RData", envir = env_classifier)
    classifier_objs <- ls(env_classifier)
    classifier_class <- sapply(classifier_objs, function(x) is(get(x, envir = env_classifier), "GeNetClassifierReturn"))
    if (!any(classifier_class)) {
        stop("Error: No GeNetClassifierReturn object found in trained_classifier.RData")
    }
    leukemiasClassifier <- get(classifier_objs[which(classifier_class)[1]], envir = env_classifier)
    
    # Load query expression data dynamically to handle any object name
    env_eset <- new.env()
    load("query_expression_data.RData", envir = env_eset)
    eset_objs <- ls(env_eset)
    eset_class <- sapply(eset_objs, function(x) is(get(x, envir = env_eset), "ExpressionSet"))
    if (!any(eset_class)) {
        stop("Error: No ExpressionSet object found in query_expression_data.RData")
    }
    queryEset <- get(eset_objs[which(eset_class)[1]], envir = env_eset)
    
    # Determine if there is a valid label column for external validation
    # Extract the classes the classifier was trained on
    classifier_classes <- names(numGenes(leukemiasClassifier@classificationGenes))
    pheno_data <- Biobase::pData(queryEset)
    label_col <- NULL
    
    # Dynamically search for a phenotype column that contains known class labels
    if (ncol(pheno_data) > 0) {
        for (col in colnames(pheno_data)) {
            if (any(as.character(pheno_data[[col]]) %in% classifier_classes)) {
                label_col <- col
                break
            }
        }
    }
    
    has_labels <- !is.null(label_col)
    
    # ==========================================
    # --- Run queryGeNetClassifier() ---
    # ==========================================
    
    queryResult <- queryGeNetClassifier(leukemiasClassifier, queryEset)
    queryResult\$class
    queryResult\$probabilities
    
    # ==========================================
    # --- Perform External Validation (if labels exist) ---
    # ==========================================
    
    if (has_labels) {
        true_labels <- as.character(pheno_data[[label_col]])
        confusionMatrix <- table(true_labels, queryResult\$class)
        valStats <- externalValidation.stats(confusionMatrix)
        valProbMatrix <- externalValidation.probMatrix(queryResult, true_labels, numDecimals=3)
    }
    
    # ==========================================
    # --- Adjust Assignment Stringency Thresholds ---
    # ==========================================
    
    queryResult_AssignAll <- queryGeNetClassifier(leukemiasClassifier, queryEset, minProbAssignCoeff=0, minDiffAssignCoeff=0)
    queryResult_AssignLess <- queryGeNetClassifier(leukemiasClassifier, queryEset, minProbAssignCoeff=1.5, minDiffAssignCoeff=1)
    
    # ==========================================
    # --- Summarize Query Results ---
    # ==========================================
    
    qSummary <- querySummary(queryResult, numDecimals=3)
    
    # ==========================================
    # --- Write Outputs ---
    # ==========================================
    
    # Save RDS objects
    saveRDS(queryResult, "query_results.rds")
    saveRDS(queryResult_AssignAll, "query_results_assign_all.rds")
    saveRDS(queryResult_AssignLess, "query_results_assign_less.rds")
    
    # Save CSV tables
    write.csv(as.data.frame(queryResult\$class), "predicted_classes.csv", row.names = TRUE)
    write.csv(as.data.frame(queryResult\$probabilities), "assignment_probabilities.csv", row.names = TRUE)
    
    if (has_labels) {
        write.csv(as.data.frame(confusionMatrix), "confusion_matrix.csv", row.names = TRUE)
        
        if (is.matrix(valStats) || is.data.frame(valStats)) {
            write.csv(valStats, "validation_stats.csv", row.names = TRUE)
        } else {
            # If it's a list of statistics, write as a text file
            sink("validation_stats.txt")
            print(valStats)
            sink()
        }
        
        write.csv(valProbMatrix, "validation_prob_matrix.csv", row.names = TRUE)
    }
    
    if (is.matrix(qSummary) || is.data.frame(qSummary)) {
        write.csv(qSummary, "query_summary.csv", row.names = TRUE)
    } else {
        sink("query_summary.txt")
        print(qSummary)
        sink()
    }
    
    # Generate PDF plots
    pdf("query_plots.pdf", width = 8, height = 6)
    tryCatch({
        plotAssignments(queryResult, main = "Query Assignments")
    }, error = function(e) {
        warning("plotAssignments failed: ", e\$message)
    })
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_GENETCLASSIFIER_QUERY_NEW_SAMPLES":',
        paste0('    geNetClassifier: ', as.character(packageVersion('geNetClassifier')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_query_new_samples.csv versions.yml
    """
}

workflow BIOC_GENETCLASSIFIER_QUERY_NEW_SAMPLES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ trained_classifier.RData, query_expression_data.RData ] ]

    main:
    BIOC_GENETCLASSIFIER_QUERY_NEW_SAMPLES(ch_input)

    emit:
    tables   = BIOC_GENETCLASSIFIER_QUERY_NEW_SAMPLES.out.tables
    plots    = BIOC_GENETCLASSIFIER_QUERY_NEW_SAMPLES.out.plots
    objects  = BIOC_GENETCLASSIFIER_QUERY_NEW_SAMPLES.out.objects
    versions = BIOC_GENETCLASSIFIER_QUERY_NEW_SAMPLES.out.versions
}
