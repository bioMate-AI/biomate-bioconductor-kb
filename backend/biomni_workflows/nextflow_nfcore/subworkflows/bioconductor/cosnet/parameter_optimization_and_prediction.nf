#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: COSNet — parameter_optimization_and_prediction
// Manually optimize network parameters on training data and run the sub-network to predict labels for unlabeled nodes.
// Input: DD.chem.data, DrugBank.Cat
// Container: quay.io/biocontainers/bioconductor-cosnet:1.44.0--r45h01b2380_0
// R packages: COSNet, PerfMeas
// Bioconductor: 3.20 | R: 4.4
// Requires: COSNet, PerfMeas
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Load the user input files
//  * 2. [Core Analysis] Prepare variables and labels
//  * 3. [Core Analysis] Execute the documented workflow steps exactly as specified
//  * 4. [Core Analysis] Evaluate and save results

nextflow.enable.dsl = 2

process BIOC_COSNET_PARAMETER_OPTIMIZATION_AND_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("COSNet", "PerfMeas")
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
    library(COSNet)
    library(PerfMeas)
    
    # Helper function to robustly load input files of various formats (RDS, RData, or text/CSV)
    load_input <- function(filepath) {
      if (!file.exists(filepath)) {
        stop(paste("Required input file not found:", filepath))
      }
      
      # Try reading as RDS
      obj <- tryCatch(readRDS(filepath), error = function(e) NULL)
      if (!is.null(obj)) return(obj)
      
      # Try loading as RData
      env <- new.env()
      tryCatch(load(filepath, envir = env), error = function(e) NULL)
      if (length(ls(env)) > 0) {
        var_names <- ls(env)
        base_name <- basename(filepath)
        if (base_name %in% var_names) {
          return(env[[base_name]])
        } else {
          return(env[[var_names[1]]])
        }
      }
      
      # Try reading as space/tab-separated table
      obj <- tryCatch(as.matrix(read.table(filepath, header = TRUE, row.names = 1, check.names = FALSE)), error = function(e) NULL)
      if (!is.null(obj)) return(obj)
      
      # Try reading as CSV
      obj <- tryCatch(as.matrix(read.csv(filepath, header = TRUE, row.names = 1, check.names = FALSE)), error = function(e) NULL)
      if (!is.null(obj)) return(obj)
      
      stop(paste("Could not parse file format for:", filepath))
    }
    
    # --- Load the user input files ---
    DD.chem.data <- load_input("DD.chem.data")
    DrugBank.Cat <- load_input("DrugBank.Cat")
    
    # Ensure inputs are matrices
    DD.chem.data <- as.matrix(DD.chem.data)
    DrugBank.Cat <- as.matrix(DrugBank.Cat)
    
    # --- Prepare variables and labels ---
    n <- nrow(DD.chem.data)
    drugs <- rownames(DD.chem.data)
    
    # Select a drug category (default to "Cephalosporins" if present, otherwise use the first column)
    drug.category <- "Cephalosporins"
    if (!(drug.category %in% colnames(DrugBank.Cat))) {
      drug.category <- colnames(DrugBank.Cat)[1]
    }
    
    labels <- as.vector(DrugBank.Cat[, drug.category])
    names(labels) <- rownames(DrugBank.Cat)
    
    # --- Execute the documented workflow steps exactly as specified ---
    folds <- find.division.strat(labels, 1:n, 5)
    labels[labels <= 0] <- -1;
    test.drugs <- folds[[1]];
    training.drugs <- setdiff(1:n, test.drugs);
    labels[test.drugs] <- 0;
    
    points <- generate_points(DD.chem.data, test.drugs, labels);
    
    opt_parameters <- optimizep(points\$pos_vect[training.drugs],
                    points\$neg_vect[training.drugs], labels[training.drugs]);
    
    alpha <- opt_parameters\$alpha;
    gamma <- opt_parameters\$c;
    Fscore <- opt_parameters\$Fscore;
    
    res <- runSubnet(DD.chem.data, labels, alpha, gamma, cost=0.035);
    
    # --- Evaluate and save results ---
    # Retrieve original labels for the test set to compute performance metrics
    orig_labels <- as.vector(DrugBank.Cat[, drug.category])
    names(orig_labels) <- rownames(DrugBank.Cat)
    test.names <- names(res\$scores)
    
    # Compute AUC and F-score on the test set
    auc_val <- tryCatch({
      AUC.single(res\$scores, orig_labels[test.names])
    }, error = function(e) {
      NA
    })
    
    f_measure_res <- tryCatch({
      F.measure.single(res\$state, orig_labels[test.names])
    }, error = function(e) {
      NULL
    })
    
    f_val <- if (!is.null(f_measure_res) && "F" %in% names(f_measure_res)) {
      f_measure_res[["F"]]
    } else {
      NA
    }
    
    # Save metrics to a CSV file
    metrics_df <- data.frame(
      Metric = c("Optimized_Alpha", "Optimized_Gamma", "Training_Fscore", "Test_AUC", "Test_Fscore"),
      Value = c(alpha, gamma, Fscore, auc_val, f_val)
    )
    write.csv(metrics_df, "cosnet_optimization_metrics.csv", row.names = FALSE)
    
    # Save predictions to a CSV file
    predictions_df <- data.frame(
      Drug = test.names,
      Predicted_State = res\$state,
      Score = res\$scores,
      True_Label = orig_labels[test.names]
    )
    write.csv(predictions_df, "cosnet_predictions.csv", row.names = FALSE)
    
    # Save the complete result object as an RDS file
    saveRDS(res, "cosnet_results.rds")

    writeLines(c(
        '"BIOC_COSNET_PARAMETER_OPTIMIZATION_AND_PREDICTION":',
        paste0('    COSNet: ', as.character(packageVersion('COSNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_parameter_optimization_and_prediction.csv versions.yml
    """
}

workflow BIOC_COSNET_PARAMETER_OPTIMIZATION_AND_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ DD.chem.data, DrugBank.Cat ] ]

    main:
    BIOC_COSNET_PARAMETER_OPTIMIZATION_AND_PREDICTION(ch_input)

    emit:
    tables   = BIOC_COSNET_PARAMETER_OPTIMIZATION_AND_PREDICTION.out.tables
    plots    = BIOC_COSNET_PARAMETER_OPTIMIZATION_AND_PREDICTION.out.plots
    objects  = BIOC_COSNET_PARAMETER_OPTIMIZATION_AND_PREDICTION.out.objects
    versions = BIOC_COSNET_PARAMETER_OPTIMIZATION_AND_PREDICTION.out.versions
}
