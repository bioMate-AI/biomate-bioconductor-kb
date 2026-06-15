#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SPONGE — sponge_effects_classification
// Define ceRNA modules, calculate enrichment scores per sample, and train/validate a subtype classification model.
// Input: train_cancer_gene_expr, test_cancer_gene_expr, train_ceRNA_interactions, train_network_centralities, train_cancer_metadata, test_cancer_metadata
// Container: quay.io/biocontainers/bioconductor-sponge:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SPONGE, caret, dplyr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter ceRNA network and compute weighted centralities
//  * 2. [Core Analysis] Identify central nodes/modules
//  * 3. [Input & Preparation] Define SPONGE modules
//  * 4. [Core Analysis] Calculate enrichment scores per sample
//  * 5. [Core Analysis] Calibrate classification model
//  * 6. [Core Analysis] Predict on test set and evaluate

nextflow.enable.dsl = 2

process BIOC_SPONGE_SPONGE_EFFECTS_CLASSIFICATION {
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
    .bm_deps <- c("SPONGE", "dplyr", "caret")
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
        
        # Load libraries
        library(SPONGE)
        library(dplyr)
        library(caret)
        
        # Helper function to read inputs
        read_input <- function(name) {
          # Try RDS first
          if (file.exists(paste0(name, ".rds"))) {
            return(readRDS(paste0(name, ".rds")))
          } else if (file.exists(name)) {
            return(readRDS(name))
          } else if (file.exists(paste0(name, ".csv"))) {
            df <- read.csv(paste0(name, ".csv"), row.names = 1, check.names = FALSE)
            if (grepl("expr", name)) {
              return(as.matrix(df))
            }
            return(df)
          } else {
            stop(paste("Required input file not found:", name))
          }
        }
        
        # Read inputs
        train_cancer_gene_expr <- read_input("train_cancer_gene_expr")
        test_cancer_gene_expr <- read_input("test_cancer_gene_expr")
        train_ceRNA_interactions <- read_input("train_ceRNA_interactions")
        train_network_centralities <- read_input("train_network_centralities")
        train_cancer_metadata <- read_input("train_cancer_metadata")
        test_cancer_metadata <- read_input("test_cancer_metadata")
        
        # Ensure expression datasets are matrices
        train_cancer_gene_expr <- as.matrix(train_cancer_gene_expr)
        test_cancer_gene_expr <- as.matrix(test_cancer_gene_expr)
        
        # Handle ensembl.df annotation
        ensembl.df <- NULL
        if (exists("ensembl.df", envir = .GlobalEnv)) {
          ensembl.df <- get("ensembl.df", envir = .GlobalEnv)
        } else {
          ensembl.df <- tryCatch({
            get("ensembl.df", envir = asNamespace("SPONGE"))
          }, error = function(e) {
            data.frame(
              ensembl_gene_id = unique(c(rownames(train_cancer_gene_expr), rownames(test_cancer_gene_expr))),
              gene_biotype = "protein_coding",
              stringsAsFactors = FALSE
            )
          })
        }
        
        # 1. Filter ceRNA network and compute weighted centralities
        filtered_network_centralities=filter_ceRNA_network(sponge_effects = train_ceRNA_interactions, Node_Centrality = train_network_centralities,add_weighted_centrality=T, mscor.threshold = 0.01, padj.threshold = 0.1)
        
        # 2. Identify central nodes/modules
        RNAs <- c("lncRNA","protein_coding")
        RNAs.ofInterest <- ensembl.df %>% dplyr::filter(gene_biotype %in% RNAs) %>%
          dplyr::select(ensembl_gene_id)
        
        central_gene_modules<-get_central_modules(central_nodes = RNAs.ofInterest\$ensembl_gene_id,node_centrality = filtered_network_centralities\$Node_Centrality,ceRNA_class = RNAs, centrality_measure = "Weighted_Degree", cutoff = 10)
        
        # 3. Define SPONGE modules
        Sponge.modules <- define_modules(network = filtered_network_centralities\$Sponge.filtered, central.modules = central_gene_modules, remove.central = F, set.parallel = F)
        # Module size distribution
        Size.modules <- sapply(Sponge.modules, length)
        
        # 4. Calculate enrichment scores per sample
        train.modules <- enrichment_modules(Expr.matrix = train_cancer_gene_expr, modules = Sponge.modules, bin.size = 10, min.size = 1, max.size = 2000, min.expr = 1, method = "OE", cores=1)
        test.modules <-  enrichment_modules(Expr.matrix = test_cancer_gene_expr, modules = Sponge.modules, bin.size = 10, min.size = 1, max.size = 2000, min.expr = 1, method = "OE", cores=1)
        
        # We find modules that were identified both in the train and test and use those as input features for the model
        common_modules = intersect(rownames(train.modules), rownames(test.modules))
        train.modules = train.modules[common_modules, ]
        test.modules = test.modules[common_modules, ]
        
        # 5. Calibrate classification model
        trained.model = calibrate_model(Input = train.modules, modules_metadata = train_cancer_metadata, label = "SUBTYPE", sampleIDs = "sampleID",Metric = "Exact_match", n_folds = 2, repetitions = 1)
        
        # 6. Predict on test set and evaluate
        tryCatch({
          Input.test <- t(test.modules) %>% scale(center = T, scale = T)
          Prediction.model <- predict(trained.model\$Model, Input.test)
        
          # We compute the confusion matrix on the test set
          ConfusionMatrix_testing <- caret::confusionMatrix(as.factor(Prediction.model), as.factor(test_cancer_metadata\$SUBTYPE))
          trained.model\$ConfusionMatrix_testing<-ConfusionMatrix_testing
          
          # Save prediction results
          write.csv(data.frame(SampleID = rownames(Input.test), Predicted_Subtype = Prediction.model), "test_predictions.csv", row.names = FALSE)
          capture.output(print(ConfusionMatrix_testing), file = "confusion_matrix_testing.txt")
        }, error = function(e) {
          warning("Prediction or evaluation on test set failed: ", e\$message)
        })
        
        # Save main outputs
        saveRDS(filtered_network_centralities, "filtered_network_centralities.rds")
        saveRDS(Sponge.modules, "sponge_modules.rds")
        write.csv(train.modules, "train_modules_enrichment.csv", row.names = TRUE)
        write.csv(test.modules, "test_modules_enrichment.csv", row.names = TRUE)
        saveRDS(trained.model, "trained_model.rds")

    writeLines(c(
        '"BIOC_SPONGE_SPONGE_EFFECTS_CLASSIFICATION":',
        paste0('    SPONGE: ', as.character(packageVersion('SPONGE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sponge_effects_classification.csv versions.yml
    """
}

workflow BIOC_SPONGE_SPONGE_EFFECTS_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ train_cancer_gene_expr, test_cancer_gene_expr, train_ceRNA_interactions, train_network_centralities, train_cancer_metadata, test_cancer_metadata ] ]

    main:
    BIOC_SPONGE_SPONGE_EFFECTS_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_SPONGE_SPONGE_EFFECTS_CLASSIFICATION.out.tables
    plots    = BIOC_SPONGE_SPONGE_EFFECTS_CLASSIFICATION.out.plots
    objects  = BIOC_SPONGE_SPONGE_EFFECTS_CLASSIFICATION.out.objects
    versions = BIOC_SPONGE_SPONGE_EFFECTS_CLASSIFICATION.out.versions
}
