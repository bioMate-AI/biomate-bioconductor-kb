#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fgga — fgga_annotation_workflow
// Predict hierarchically consistent Gene Ontology (GO) annotations for protein sequences using a factor graph ensemble of SVM classifiers.
// Input: dxCf, tableCfGO, nodesGO
// Container: quay.io/biocontainers/bioconductor-fgga:1.18.0--r45hdfd78af_0
// R packages: GO.db, Rgraphviz, fgga, GOstats, knitr, pROC
// Bioconductor: 3.20 | R: 4.4
// Requires: GO.db, GOstats, Rgraphviz, fgga, pROC
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build the GO subgraph and identify the root node
//  * 2. [Core Analysis] Map the GO subgraph to a bipartite factor graph
//  * 3. [Core Analysis] Train binary SVM classifiers for each GO term
//  * 4. [Core Analysis] Calculate the reliability (variance) of each GO term
//  * 5. [Core Analysis] Predict flat GO-term probabilities for test sequences
//  * 6. [Core Analysis] Compute marginal probabilities using the iterative message-passing algorithm
//  * 7. [Core Analysis] Evaluate prediction performance using hierarchical measures

nextflow.enable.dsl = 2

process BIOC_FGGA_FGGA_ANNOTATION_WORKFLOW {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("GO.db", "Rgraphviz", "fgga", "GOstats", "knitr", "pROC")
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
    library(fgga)
    library(GO.db)
    library(GOstats)
    library(pROC)
    library(Rgraphviz)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    load_input <- function(name) {
      rds_file <- paste0(name, ".rds")
      csv_file <- paste0(name, ".csv")
      txt_file <- paste0(name, ".txt")
      
      if (file.exists(rds_file)) {
        return(readRDS(rds_file))
      } else if (file.exists(csv_file)) {
        df <- read.csv(csv_file, header = TRUE, row.names = 1, check.names = FALSE)
        return(as.matrix(df))
      } else if (file.exists(txt_file)) {
        return(readLines(txt_file))
      } else {
        stop(paste("Required input file not found for:", name))
      }
    }
    
    # Load the three required user inputs
    dxCf <- load_input("dxCf")
    tableCfGO <- load_input("tableCfGO")
    nodesGO <- load_input("nodesGO")
    
    # Ensure nodesGO is a character vector
    if (is.matrix(nodesGO) || is.data.frame(nodesGO)) {
      nodesGO <- as.character(nodesGO[[1]])
    }
    
    # ==========================================
    # 2. Preprocessing & Filtering (Pitfalls)
    # ==========================================
    # FGGA requires at least 50 annotations per GO-term to train the model.
    # Filter out terms that do not meet this requirement.
    go_counts <- colSums(tableCfGO)
    valid_go <- names(go_counts)[go_counts >= 50]
    nodesGO <- intersect(nodesGO, valid_go)
    tableCfGO <- tableCfGO[, nodesGO, drop = FALSE]
    
    # Ensure row names match between features and annotations
    common_proteins <- intersect(rownames(dxCf), rownames(tableCfGO))
    dxCf <- dxCf[common_proteins, , drop = FALSE]
    tableCfGO <- tableCfGO[common_proteins, , drop = FALSE]
    
    # Define train and test splits dynamically based on available data
    n_total <- length(common_proteins)
    train_size <- min(750, floor(n_total * 0.8))
    test_size <- min(50, n_total - train_size)
    
    if (train_size < 10 || test_size < 1) {
      stop("Insufficient data size for training and testing splits.")
    }
    
    idsTrain <- common_proteins[1:train_size]
    idsTest <- common_proteins[(train_size + 1):(train_size + test_size)]
    
    # ==========================================
    # 3. Build GO Subgraph & Identify Root Node
    # ==========================================
    # Use GOGraph instead of preCoreFG to prevent adding parent nodes not present in tableCfGO
    mygraph <- GOGraph(nodesGO, GOMFPARENTS)
    mygraph <- subGraph(nodesGO, mygraph)
    mygraph <- t(as(mygraph, "matrix"))
    mygraphGO <- as(mygraph, "graphNEL")
    
    # Ensure the graph only contains nodes present in tableCfGO to prevent missing column errors
    nodesGO <- intersect(nodes(mygraphGO), colnames(tableCfGO))
    mygraphGO <- subGraph(nodesGO, mygraphGO)
    tableCfGO <- tableCfGO[, nodesGO, drop = FALSE]
    
    rootGO <- leaves(mygraphGO, "in")
    
    # Save GO Graph Plot
    pdf("mygraphGO.pdf", width = 10, height = 8)
    plot(mygraphGO)
    dev.off()
    
    # ==========================================
    # 4. Map GO Subgraph to Bipartite Factor Graph
    # ==========================================
    modelFGGA <- fgga2bipartite(mygraphGO)
    
    # ==========================================
    # 5. Train Binary SVM Classifiers
    # ==========================================
    modelSVMs <- lapply(nodesGO, FUN = svmTrain, 
                        tableOntoTerms = tableCfGO[idsTrain, ], 
                        dxCharacterized = dxCf[idsTrain, ], 
                        graphOnto = mygraphGO, kernelSVM = "radial")
    
    # ==========================================
    # 6. Calculate Reliability (Variance) of GO Terms
    # ==========================================
    varianceGOs <- varianceOnto(tableOntoTerms = tableCfGO[idsTrain, ],
                                dxCharacterized = dxCf[idsTrain, ],
                                kFold = 5, graphOnto = mygraphGO, rootNode = rootGO,
                                kernelSVM = "radial")
    
    # ==========================================
    # 7. Predict Flat GO-Term Probabilities
    # ==========================================
    dxTestCharacterized <- dxCf[idsTest, ]
    
    matrixGOTest <- svmOnto(svmMoldel = modelSVMs, 
                            dxCharacterized = dxTestCharacterized, 
                            rootNode = rootGO, 
                            varianceSVM = varianceGOs)
    
    # ==========================================
    # 8. Compute Marginal Probabilities (Message Passing)
    # ==========================================
    matrixFGGATest <- t(apply(matrixGOTest, MARGIN = 1, FUN = msgFGGA, 
                              matrixFGGA = modelFGGA, graphOnto = mygraphGO,
                              tmax = 50, epsilon = 0.001))
    
    # Save predicted marginal probabilities
    write.csv(matrixFGGATest, "matrixFGGATest.csv", row.names = TRUE)
    
    # ==========================================
    # 9. Evaluate Prediction Performance
    # ==========================================
    # Hierarchical Measures
    hierarchical_measures <- fHierarchicalMeasures(tableCfGO[rownames(matrixFGGATest), ], 
                                                   matrixFGGATest, mygraphGO)
    saveRDS(hierarchical_measures, "hierarchical_measures.rds")
    
    # Standard F-Measures
    Fs <- fMeasures(tableCfGO[rownames(matrixFGGATest), ], matrixFGGATest)
    saveRDS(Fs, "fMeasures_results.rds")
    
    # ROC and Precision-Recall Analysis for the first GO term
    tryCatch({
      rocGO <- roc(tableCfGO[rownames(matrixFGGATest), 1], matrixFGGATest[, 1])
      auc_val <- auc(rocGO)
      
      # Save ROC Plot
      pdf("roc_first_term.pdf")
      plot(rocGO, main = paste("ROC Curve - First GO Term\nAUC =", round(auc_val, 4)))
      dev.off()
      
      # Precision at different recall levels
      rocGO_pct <- roc(tableCfGO[rownames(matrixFGGATest), 1], matrixFGGATest[, 1], percent = TRUE)
      PXR <- coords(rocGO_pct, "all", ret = c("recall", "precision"), transpose = FALSE)
      avg_pxr <- mean(PXR\$precision[!is.na(PXR\$precision)])
      
      # Save text summary of performance
      sink("performance_summary.txt")
      cat("=== FGGA Performance Summary ===\n\n")
      cat("Hierarchical Measures:\n")
      print(hierarchical_measures)
      cat("\nAverage F-score (All Terms):\n")
      print(mean(Fs\$perfByTerms, na.rm = TRUE))
      cat("\nFirst GO Term AUC:\n")
      print(auc_val)
      cat("\nFirst GO Term Average PxR:\n")
      print(avg_pxr)
      sink()
    }, error = function(e) {
      warning("ROC/PxR evaluation skipped or failed: ", e\$message)
    })

    writeLines(c(
        '"BIOC_FGGA_FGGA_ANNOTATION_WORKFLOW":',
        paste0('    fgga: ', as.character(packageVersion('fgga')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fgga_annotation_workflow.csv versions.yml
    """
}

workflow BIOC_FGGA_FGGA_ANNOTATION_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dxCf, tableCfGO, nodesGO ] ]

    main:
    BIOC_FGGA_FGGA_ANNOTATION_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_FGGA_FGGA_ANNOTATION_WORKFLOW.out.tables
    plots    = BIOC_FGGA_FGGA_ANNOTATION_WORKFLOW.out.plots
    objects  = BIOC_FGGA_FGGA_ANNOTATION_WORKFLOW.out.objects
    versions = BIOC_FGGA_FGGA_ANNOTATION_WORKFLOW.out.versions
}
