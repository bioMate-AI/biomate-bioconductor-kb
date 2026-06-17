#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Pigengene — step_by_step_pipeline
// Run the Pigengene pipeline step-by-step to customize parameters, learn a Bayesian network, fit parameters, predict labels, build decision trees, and perform pat
// Input: expression_matrix.csv, sample_labels.csv
// Container: quay.io/biocontainers/bioconductor-pigengene:1.32.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Pigengene, bnlearn, org.Hs.eg.db
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Quality control with check.pigengene.input
//  * 2. [Core Analysis] Balance sample sizes with balance
//  * 3. [Core Analysis] Estimate soft-thresholding power beta with calculate.beta
//  * 4. [Core Analysis] Identify gene modules using wgcna.one.step
//  * 5. [Core Analysis] Compute eigengenes with compute.pigengene
//  * 6. [Core Analysis] Learn Bayesian network structure with learn.bn
//  * 7. [Core Analysis] Fit Bayesian network parameters with bn.fit
//  * 8. [Core Analysis] Predict disease labels with predict
//  * 9. [Input & Preparation] Build decision trees with make.decision.tree
//  * 10. [Core Analysis] Perform pathway enrichment analysis with get.enriched.pw

nextflow.enable.dsl = 2

process BIOC_PIGENGENE_STEP_BY_STEP_PIPELINE {
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
    .bm_deps <- c("Pigengene", "bnlearn", "org.Hs.eg.db")
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
    library(Pigengene)
    library(bnlearn)
    library(org.Hs.eg.db)
    
    # 1. Read User Input Files
    if (!file.exists("expression_matrix.csv")) {
      stop("Error: expression_matrix.csv not found in the working directory.")
    }
    if (!file.exists("sample_labels.csv")) {
      stop("Error: sample_labels.csv not found in the working directory.")
    }
    
    # Read expression matrix (samples as rows, genes as columns)
    Data <- read.csv("expression_matrix.csv", row.names=1, check.names=FALSE)
    Data <- as.matrix(Data)
    class(Data) <- "numeric"
    
    # Read sample labels
    labels_df <- read.csv("sample_labels.csv", header=TRUE, stringsAsFactors=FALSE)
    
    # Format Labels as a named character vector
    if (ncol(labels_df) >= 2) {
      Labels <- as.character(labels_df[[2]])
      names(Labels) <- as.character(labels_df[[1]])
    } else {
      Labels <- as.character(labels_df[[1]])
      if (!is.null(rownames(labels_df)) && !all(rownames(labels_df) == as.character(1:nrow(labels_df)))) {
        names(Labels) <- rownames(labels_df)
      } else {
        names(Labels) <- rownames(Data)
      }
    }
    
    # Align samples between expression matrix and labels
    common_samples <- intersect(rownames(Data), names(Labels))
    if (length(common_samples) == 0) {
      names(Labels) <- rownames(Data)
    } else {
      Data <- Data[common_samples, , drop=FALSE]
      Labels <- Labels[common_samples]
    }
    
    ## QC:
    checked <- check.pigengene.input(Data=Data, Labels=Labels)
    DataI <- checked\$Data
    LabelsI <- checked\$Labels
    
    ## Balance:
    wData <- balance(Data=DataI, Labels=LabelsI, verbose=1)\$balanced
    
    ## Beta:
    betaI <- calculate.beta(RsquaredCut=0.8, Data=wData, verbose=1)\$power
    if (is.na(betaI) || is.null(betaI)) {
      message("Warning: RsquaredCut threshold of 0.8 not met. Defaulting soft-thresholding power beta to 9.")
      betaI <- 9
    }
    
    saveDir <- "steps" ## Results will be saved in this folder.
    if (!dir.exists(saveDir)) {
      dir.create(saveDir, recursive=TRUE)
    }
    
    ## WGCNA
    wgRes <- wgcna.one.step(Data=wData, seed=1, power=betaI,
          saveDir=saveDir, verbose=1)
    
    ## Eigengenes:
    pigengene <- compute.pigengene(Data=DataI, Labels=LabelsI,
    	     	saveFile=file.path(saveDir, 'pigengene.RData'),
                    modules=wgRes\$modules, verbose=1)
    
    # Save eigengenes matrix to CSV
    write.csv(pigengene\$eigengenes, file=file.path(saveDir, "eigengenes.csv"), row.names=TRUE)
    
    ## Learning the BN structure:
    learnt <- learn.bn(pigengene=pigengene, bnPath=file.path(saveDir, "bn"),
           	  	bnNum=10, ## In real applications, at least 100-1000.
    		seed=1, verbose=1)
    BN <- learnt\$consensus1\$BN
    saveRDS(BN, file=file.path(saveDir, "consensus_BN.rds"))
    
    ## Fit the parameters of the Bayesian network:
    fit <- bn.fit(x=BN, data=learnt\$consensus1\$Data, method="bayes", iss=10)
    saveRDS(fit, file=file.path(saveDir, "bn_fit.rds"))
    
    ## The conditional probability table for one of the children of the Disease node:
    selectedFeatures <- children("Disease", x=BN)
    if (length(selectedFeatures) == 0) {
      message("Warning: 'Disease' node has no children in the learned network. Using all other nodes as selected features.")
      selectedFeatures <- setdiff(nodes(BN), "Disease")
    }
    if (length(selectedFeatures) == 0) {
      selectedFeatures <- "All"
    }
    
    if (selectedFeatures[1] != "All" && length(selectedFeatures) > 0) {
      sink(file.path(saveDir, "conditional_probability_table.txt"))
      print(fit[[selectedFeatures[1]]])
      sink()
    }
    
    ## Prediction:
    l2 <- predict(object=fit, node="Disease", data=learnt\$consensus1\$Data, method="bayes-lw")
    pred_table <- table(LabelsI, l2)
    write.csv(as.data.frame.matrix(pred_table), file=file.path(saveDir, "prediction_confusion_matrix.csv"))
    
    ## Decision trees:
    treePath <- file.path(saveDir, 'C5Trees')
    if (!dir.exists(treePath)) {
      dir.create(path=treePath, recursive=TRUE)
    }
    treeRes <- make.decision.tree(pigengene=pigengene, Data=DataI,
    	       selectedFeatures=selectedFeatures, saveDir=treePath,
           	       verbose=1, toCompact=FALSE)
    saveRDS(treeRes, file=file.path(treePath, "decision_tree_results.rds"))
    
    ## Access tree results dynamically to avoid missing key errors
    treeKey <- "17"
    if (!treeKey %in% names(treeRes\$c5Trees)) {
      treeKey <- names(treeRes\$c5Trees)[1]
    }
    
    if (!is.null(treeKey) && length(treeRes\$c5Trees) > 0) {
      usedFeatures <- get.used.features(c5Tree=treeRes\$c5Trees[[treeKey]])
      moduleMembers <- setNames(paste0("ME", wgRes\$modules), 
                                nm=sub("_[^_]+\$", "", names(wgRes\$modules)))
      modMembersUsed <- moduleMembers[moduleMembers %in% usedFeatures]
      moduList <- split(names(modMembersUsed), f=modMembersUsed)
    
      pw1 <- tryCatch({
        get.enriched.pw(genes=moduList, idType="ENTREZID", pathwayDb="KEGG",
                        Org=NULL, OrgDb=org.Hs.eg.db, outPath=saveDir, verbose=1)
      }, error = function(e) {
        message("Pathway enrichment failed or skipped: ", e\$message)
        NULL
      })
      if (!is.null(pw1)) {
        saveRDS(pw1, file=file.path(saveDir, "pathway_enrichment_results.rds"))
      }
    } else {
      message("No decision trees were generated. Skipping pathway enrichment.")
    }
    
    message("Pipeline completed successfully. Results are saved in the '", saveDir, "' directory.")

    writeLines(c(
        '"BIOC_PIGENGENE_STEP_BY_STEP_PIPELINE":',
        paste0('    Pigengene: ', as.character(packageVersion('Pigengene')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_pipeline.csv versions.yml
    """
}

workflow BIOC_PIGENGENE_STEP_BY_STEP_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, sample_labels.csv ] ]

    main:
    BIOC_PIGENGENE_STEP_BY_STEP_PIPELINE(ch_input)

    emit:
    tables   = BIOC_PIGENGENE_STEP_BY_STEP_PIPELINE.out.tables
    plots    = BIOC_PIGENGENE_STEP_BY_STEP_PIPELINE.out.plots
    objects  = BIOC_PIGENGENE_STEP_BY_STEP_PIPELINE.out.objects
    versions = BIOC_PIGENGENE_STEP_BY_STEP_PIPELINE.out.versions
}
