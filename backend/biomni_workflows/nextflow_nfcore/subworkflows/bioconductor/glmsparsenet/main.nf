#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: glmSparseNet — survival_analysis_cox
// Fit a network-penalized Cox proportional hazards model to survival data using a protein-protein interaction network.
// Input: xdata, ydata
// Container: quay.io/biocontainers/bioconductor-glmsparsenet:1.28.0--r45hdfd78af_0
// R packages: biocmanager, ggplot2, glmSparseNet, Matrix, MultiAssayExperiment, survival, TCGAutils, VennDiagram
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, ggplot2, glmSparseNet, survival
// Visualizations: survival plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Retrieve and build the network matrix from STRING DB using stringDBhomoSapiens and buildStringNetwork
//  * 2. [Core Analysis] Generate balanced cross-validation folds using glmSparseNet:::balancedCvFolds
//  * 3. [Core Analysis] Fit the network-penalized Cox model using cv.glmHub or cv.glmOrphan
//  * 4. [Core Analysis] Evaluate the model using Kaplan-Meier survival curves via separate2GroupsCox

nextflow.enable.dsl = 2

process BIOC_GLMSPARSENET_SURVIVAL_ANALYSIS_COX {
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
    .bm_deps <- c("biocmanager", "ggplot2", "glmSparseNet", "Matrix", "MultiAssayExperiment", "survival", "TCGAutils", "VennDiagram")
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
    library(glmSparseNet)
    library(survival)
    library(Matrix)
    library(ggplot2)
    
    # ----------------------------------------------------------------------
    # 1. Read User Input Files
    # ----------------------------------------------------------------------
    # Read xdata (matrix of gene expression values: columns = genes, rows = samples)
    if (file.exists("xdata.rds")) {
      xdata <- readRDS("xdata.rds")
    } else if (file.exists("xdata.csv")) {
      xdata <- as.matrix(read.csv("xdata.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: xdata file not found. Please provide 'xdata.rds' or 'xdata.csv' in the working directory.")
    }
    
    # Read ydata (data frame containing survival 'time' and 'status' columns)
    if (file.exists("ydata.rds")) {
      ydata <- readRDS("ydata.rds")
    } else if (file.exists("ydata.csv")) {
      ydata <- read.csv("ydata.csv", row.names = 1, check.names = FALSE)
    } else {
      stop("Error: ydata file not found. Please provide 'ydata.rds' or 'ydata.csv' in the working directory.")
    }
    
    # Ensure ydata columns are numeric and clean up non-positive survival times
    ydata\$time <- as.numeric(ydata\$time)
    ydata\$status <- as.numeric(ydata\$status)
    
    valid_indices <- !is.na(ydata\$time) & ydata\$time > 0 & !is.na(ydata\$status)
    ydata <- ydata[valid_indices, , drop = FALSE]
    xdata <- xdata[valid_indices, , drop = FALSE]
    
    if (nrow(xdata) == 0) {
      stop("Error: No valid samples remaining after filtering for positive survival times.")
    }
    
    # ----------------------------------------------------------------------
    # 2. Retrieve and Build the Network Matrix from STRING DB
    # ----------------------------------------------------------------------
    allInteractions700 <- stringDBhomoSapiens(scoreThreshold = 700)
    stringNetwork <- buildStringNetwork(allInteractions700, "external")
    stringNetworkUndirected <- stringNetwork + Matrix::t(stringNetwork)
    stringNetworkUndirected <- (stringNetworkUndirected != 0) * 1
    
    # Construct myString matching the features present in xdata
    genes <- colnames(xdata)
    myString <- Matrix::Matrix(0, nrow = length(genes), ncol = length(genes), sparse = TRUE, dimnames = list(genes, genes))
    common_genes <- intersect(genes, colnames(stringNetworkUndirected))
    if (length(common_genes) > 0) {
      myString[common_genes, common_genes] <- stringNetworkUndirected[common_genes, common_genes]
    }
    
    # ----------------------------------------------------------------------
    # 3. Generate Balanced Cross-Validation Folds
    # ----------------------------------------------------------------------
    foldid <- glmSparseNet:::balancedCvFolds(ydata\$status)\$output
    
    # ----------------------------------------------------------------------
    # 4. Fit the Network-Penalized Cox Models
    # ----------------------------------------------------------------------
    # Fit Hub model
    resultCVHub <- cv.glmHub(
      xdata, 
      Surv(ydata\$time, ydata\$status), 
      family = "cox", 
      foldid = foldid, 
      network = myString, 
      network.options = networkOptions(minDegree = 0.2) 
    )
    
    # Fit Orphan model
    resultCVOrphan <- cv.glmOrphan(
      xdata, 
      Surv(ydata\$time, ydata\$status), 
      family = "cox", 
      foldid = foldid, 
      network = myString, 
      network.options = networkOptions(minDegree = 0.2) 
    )
    
    # Save fitted model objects
    saveRDS(resultCVHub, "resultCVHub.rds")
    saveRDS(resultCVOrphan, "resultCVOrphan.rds")
    
    # ----------------------------------------------------------------------
    # 5. Evaluate Models and Generate Outputs
    # ----------------------------------------------------------------------
    
    # --- Process Hub Model ---
    fitted <- resultCVHub
    coefsCV <- Filter(function(.x) .x != 0, coef(fitted, s = "lambda.min")[, 1])
    
    # Save coefficients to CSV
    write.csv(
      data.frame(Gene = names(coefsCV), Coefficient = as.vector(coefsCV)), 
      "coefs_Hub.csv", 
      row.names = FALSE
    )
    
    # Generate Kaplan-Meier survival curves for Hub Model
    if (length(coefsCV) > 0) {
      pdf("survival_plot_Hub.pdf", width = 8, height = 6)
      tryCatch({
        surv_eval <- separate2GroupsCox(
          as.vector(coefsCV), 
          xdata[, names(coefsCV), drop = FALSE], 
          ydata, 
          plotTitle = "Full dataset - Hub Model", 
          legendOutside = FALSE 
        )
        print(surv_eval\$plot)
      }, error = function(e) {
        message("Warning: Could not generate survival plot for Hub model: ", e\$message)
      })
      dev.off()
    }
    
    # --- Process Orphan Model ---
    fitted <- resultCVOrphan
    coefsCV_orphan <- Filter(function(.x) .x != 0, coef(fitted, s = "lambda.min")[, 1])
    
    # Save coefficients to CSV
    write.csv(
      data.frame(Gene = names(coefsCV_orphan), Coefficient = as.vector(coefsCV_orphan)), 
      "coefs_Orphan.csv", 
      row.names = FALSE
    )
    
    # Generate Kaplan-Meier survival curves for Orphan Model
    if (length(coefsCV_orphan) > 0) {
      pdf("survival_plot_Orphan.pdf", width = 8, height = 6)
      tryCatch({
        surv_eval_orphan <- separate2GroupsCox(
          as.vector(coefsCV_orphan), 
          xdata[, names(coefsCV_orphan), drop = FALSE], 
          ydata, 
          plotTitle = "Full dataset - Orphan Model", 
          legendOutside = FALSE 
        )
        print(surv_eval_orphan\$plot)
      }, error = function(e) {
        message("Warning: Could not generate survival plot for Orphan model: ", e\$message)
      })
      dev.off()
    }
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_GLMSPARSENET_SURVIVAL_ANALYSIS_COX":',
        paste0('    glmSparseNet: ', as.character(packageVersion('glmSparseNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_survival_analysis_cox.csv versions.yml
    """
}

workflow BIOC_GLMSPARSENET_SURVIVAL_ANALYSIS_COX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ xdata, ydata ] ]

    main:
    BIOC_GLMSPARSENET_SURVIVAL_ANALYSIS_COX(ch_input)

    emit:
    tables   = BIOC_GLMSPARSENET_SURVIVAL_ANALYSIS_COX.out.tables
    plots    = BIOC_GLMSPARSENET_SURVIVAL_ANALYSIS_COX.out.plots
    objects  = BIOC_GLMSPARSENET_SURVIVAL_ANALYSIS_COX.out.objects
    versions = BIOC_GLMSPARSENET_SURVIVAL_ANALYSIS_COX.out.versions
}
