#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iterativeBMAsurv — step_by_step_survival_analysis
// Train the iterative BMA model step-by-step, predict risk scores for test samples, assign them to risk categories, evaluate survival differences, and visualize t
// Input: trainData, trainSurv, trainCens, testData, testSurv, testCens
// Container: quay.io/biocontainers/bioconductor-iterativebmasurv:1.68.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iterativeBMAsurv, survival
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load training data and run iterateBMAsurv.train.wrapper to select relevant genes
//  * 2. [Core Analysis] Extract the bic.surv object and identify top genes with posterior probability > 0
//  * 3. [Input & Preparation] Load test data and subset it to the selected top genes
//  * 4. [Core Analysis] Predict risk scores for test and training samples using predictBicSurv
//  * 5. [Core Analysis] Assign test samples to risk categories using predictiveAssessCategory
//  * 6. [Core Analysis] Perform survival difference analysis using survdiff
//  * 7. [Visualization & Output] Visualize selected genes and models using imageplot.iterate.bma.surv

nextflow.enable.dsl = 2

process BIOC_ITERATIVEBMASURV_STEP_BY_STEP_SURVIVAL_ANALYSIS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(BMA)
    library(iterativeBMAsurv)
    library(survival)
    
    # Robust helper function to load user input files
    load_input <- function(name) {
      file_path <- name
      if (!file.exists(file_path)) {
        for (ext in c(".rds", ".csv", ".txt", ".tsv")) {
          if (file.exists(paste0(name, ext))) {
            file_path <- paste0(name, ext)
            break
          }
        }
      }
      if (!file.exists(file_path)) {
        stop(paste("Required input file not found for:", name))
      }
      
      # Try reading as RDS first
      if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE) || !grepl("\\\\.", file_path)) {
        res <- tryCatch(readRDS(file_path), error = function(e) NULL)
        if (!is.null(res)) return(res)
      }
      
      # Fallback to delimited text files
      sep <- if (grepl("\\\\.csv\$", file_path, ignore.case = TRUE)) "," else "\t"
      df <- read.table(file_path, sep = sep, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
      
      if (ncol(df) == 1) {
        return(df[[1]])
      } else if (ncol(df) == 2 && (colnames(df)[1] == "" || colnames(df)[1] == "row.names" || colnames(df)[1] == "X")) {
        vec <- df[[2]]
        names(vec) <- df[[1]]
        return(vec)
      } else {
        if (is.character(df[[1]]) || is.factor(df[[1]])) {
          rownames(df) <- df[[1]]
          df <- df[, -1, drop = FALSE]
        }
        return(as.matrix(df))
      }
    }
    
    # 1. Load training data and run iterateBMAsurv.train.wrapper to select relevant genes
    trainData <- as.matrix(load_input("trainData"))
    trainSurv <- as.numeric(load_input("trainSurv"))
    trainCens <- as.numeric(load_input("trainCens"))
    
    ret.list <- iterateBMAsurv.train.wrapper (x=trainData, surv.time=trainSurv, cens.vec=trainCens, nbest=5)
    
    # 2. Extract the bic.surv object and identify top genes with posterior probability > 0
    ret.bic.surv <- ret.list\$obj
    gene.names <- ret.list\$curr.names
    top.gene.names <- gene.names[ret.bic.surv\$probne0 > 0]
    
    # Save selected genes and posterior probabilities
    selected_genes_df <- data.frame(
      Gene = top.gene.names, 
      ProbNe0 = ret.bic.surv\$probne0[ret.bic.surv\$probne0 > 0]
    )
    write.csv(selected_genes_df, file = "selected_genes_probabilities.csv", row.names = FALSE)
    
    # Save model posterior probabilities
    model_postprob_df <- data.frame(
      Model = seq_along(ret.bic.surv\$postprob), 
      PostProb = ret.bic.surv\$postprob
    )
    write.csv(model_postprob_df, file = "model_posterior_probabilities.csv", row.names = FALSE)
    
    # 3. Load test data and subset it to the selected top genes
    testData <- as.matrix(load_input("testData"))
    testSurv <- as.numeric(load_input("testSurv"))
    testCens <- as.numeric(load_input("testCens"))
    
    curr.test.dat <- testData[, top.gene.names, drop = FALSE]
    
    # 4. Predict risk scores for test and training samples using predictBicSurv
    y.pred.test <- apply (curr.test.dat, 1, predictBicSurv, postprob.vec=ret.bic.surv\$postprob, mle.mat=ret.bic.surv\$mle)
    y.pred.train <- apply (trainData[, top.gene.names, drop = FALSE], 1, predictBicSurv, postprob.vec=ret.bic.surv\$postprob, mle.mat=ret.bic.surv\$mle)
    
    # Save predicted risk scores
    write.csv(data.frame(Sample = names(y.pred.test), RiskScore = y.pred.test), 
              file = "test_predicted_risk_scores.csv", row.names = FALSE)
    write.csv(data.frame(Sample = names(y.pred.train), RiskScore = y.pred.train), 
              file = "train_predicted_risk_scores.csv", row.names = FALSE)
    
    # 5. Assign test samples to risk categories using predictiveAssessCategory
    ret.table <- predictiveAssessCategory (y.pred.test, y.pred.train, testCens, cutPoint=50) 
    risk.vector <- ret.table\$groups
    risk.table <- ret.table\$assign.risk
    
    # Save risk classification results
    write.csv(as.data.frame(risk.table), file = "risk_classification_table.csv")
    write.csv(data.frame(Sample = names(y.pred.test), RiskGroup = unlist(risk.vector)), 
              file = "test_risk_group_assignments.csv", row.names = FALSE)
    
    # 6. Perform survival difference analysis using survdiff
    mySurv.obj <- Surv(testSurv, testCens)
    stats <- survdiff(mySurv.obj ~ unlist(risk.vector))
    
    # Save survival difference statistics
    sink("survival_difference_stats.txt")
    print(stats)
    sink()
    
    # 7. Visualize selected genes and models using imageplot.iterate.bma.surv
    pdf("imageplot_bma_surv.pdf", width = 8, height = 8)
    imageplot.iterate.bma.surv (ret.bic.surv)
    dev.off()
    
    # Save the final bic.surv object as RDS for downstream analysis
    saveRDS(ret.bic.surv, "ret_bic_surv.rds")

    writeLines(c(
        '"BIOC_ITERATIVEBMASURV_STEP_BY_STEP_SURVIVAL_ANALYSIS":',
        paste0('    iterativeBMAsurv: ', as.character(packageVersion('iterativeBMAsurv')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_survival_analysis.csv versions.yml
    """
}

workflow BIOC_ITERATIVEBMASURV_STEP_BY_STEP_SURVIVAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ trainData, trainSurv, trainCens, testData, testSurv, testCens ] ]

    main:
    BIOC_ITERATIVEBMASURV_STEP_BY_STEP_SURVIVAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ITERATIVEBMASURV_STEP_BY_STEP_SURVIVAL_ANALYSIS.out.tables
    plots    = BIOC_ITERATIVEBMASURV_STEP_BY_STEP_SURVIVAL_ANALYSIS.out.plots
    objects  = BIOC_ITERATIVEBMASURV_STEP_BY_STEP_SURVIVAL_ANALYSIS.out.objects
    versions = BIOC_ITERATIVEBMASURV_STEP_BY_STEP_SURVIVAL_ANALYSIS.out.versions
}
