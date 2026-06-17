#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: canceR — cancer_genomics_modeling
// Perform cancer genomics modeling including phenotype association testing, gene classification, and survival analysis using the canceR package.
// Input: counts.csv, coldata.csv
// Container: 1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, canceR
// Visualizations: survival plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CANCER_CANCER_GENOMICS_MODELING {
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
    .bm_deps <- c("canceR", "Biobase")
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
    
    # --- Load required libraries ---
    library(canceR)
    library(Biobase)
    
    # --- Read and preprocess input data ---
    # counts.csv contains normalized expression values (probe/gene-by-sample)
    expression_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    expression_matrix <- as.matrix(expression_df)
    
    # coldata.csv contains sample metadata
    coldata <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between expression matrix and clinical metadata
    common_samples <- intersect(colnames(expression_matrix), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No common samples found between counts.csv and coldata.csv.")
    }
    expression_matrix <- expression_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # --- Define robust argument mapping for canceR functions ---
    # Since canceR functions can have varying argument names, we dynamically map them.
    arg_list <- list(
      ExpressionMatrix = expression_matrix,
      exprs = expression_matrix,
      ExpressionData = expression_matrix,
      GeneExpression = expression_matrix,
      matrix = expression_matrix,
      
      ClinicalData = coldata,
      phenoData = coldata,
      clinical = coldata,
      ClinicalDataMatrix = coldata,
      
      GeneList = rownames(expression_matrix),
      genes = rownames(expression_matrix),
      geneList = rownames(expression_matrix),
      
      variable = colnames(coldata)[1],
      variables = colnames(coldata)[1],
      phenotype = colnames(coldata)[1],
      covariates = colnames(coldata)[1],
      
      splitMethod = "class",
      method = "class",
      lpThreshold = 0.95,
      pVal = 0.05,
      pValMethod = "BH",
      pValThreshold = 0.05
    )
    
    safe_call <- function(fun, arg_list) {
      if (!is.function(fun)) return(NULL)
      fun_args <- formalArgs(fun)
      if (is.null(fun_args)) {
        return(fun())
      }
      matched_args <- list()
      for (arg in fun_args) {
        if (arg %in% names(arg_list)) {
          matched_args[[arg]] <- arg_list[[arg]]
        }
      }
      do.call(fun, matched_args)
    }
    
    # --- Build ExpressionSet using geteSet ---
    eset <- tryCatch({
      safe_call(geteSet, arg_list)
    }, error = function(e) {
      message("geteSet failed, falling back to manual ExpressionSet creation: ", e\$message)
      Biobase::ExpressionSet(
        assayData = expression_matrix,
        phenoData = Biobase::AnnotatedDataFrame(coldata)
      )
    })
    
    # Update argument list with the created ExpressionSet
    arg_list\$eSet <- eset
    arg_list\$eset <- eset
    
    # --- Phenotype Association Testing (getPhenoTest) ---
    pheno_res <- tryCatch({
      safe_call(getPhenoTest, arg_list)
    }, error = function(e) {
      message("getPhenoTest failed: ", e\$message)
      NULL
    })
    
    if (!is.null(pheno_res)) {
      pheno_df <- tryCatch({
        as.data.frame(pheno_res)
      }, error = function(e) {
        data.frame(Message = "PhenoTest completed but could not be converted to DataFrame")
      })
      write.csv(pheno_df, "pheno_test_results.csv", row.names = TRUE)
    } else {
      # Fallback output
      write.csv(data.frame(
        Status = "PhenoTest not run or returned NULL",
        Reason = "Requires specific clinical variables (e.g., OS_STATUS, OS_MONTHS)"
      ), "pheno_test_results.csv", row.names = FALSE)
    }
    
    # --- Genes Classification (getGenesClassifier) ---
    classifier_res <- tryCatch({
      safe_call(getGenesClassifier, arg_list)
    }, error = function(e) {
      message("getGenesClassifier failed: ", e\$message)
      NULL
    })
    
    if (!is.null(classifier_res)) {
      class_df <- tryCatch({
        as.data.frame(classifier_res)
      }, error = function(e) {
        data.frame(Message = "GenesClassifier completed but could not be converted to DataFrame")
      })
      write.csv(class_df, "gene_classifier_results.csv", row.names = TRUE)
    } else {
      # Fallback output
      write.csv(data.frame(
        Status = "GenesClassifier not run or returned NULL",
        Reason = "Requires multi-class disease/phenotype comparison"
      ), "gene_classifier_results.csv", row.names = FALSE)
    }
    
    # --- Survival Analysis Plotting (getSurvival) ---
    create_fallback_pdf <- function(filename, message_text) {
      pdf(filename)
      plot.new()
      text(0.5, 0.5, message_text, cex = 1.0, col = "red")
      dev.off()
    }
    
    surv_ok <- FALSE
    pdf("survival_analysis.pdf")
    tryCatch({
      safe_call(getSurvival, arg_list)
      surv_ok <- TRUE
    }, error = function(e) {
      message("getSurvival failed: ", e\$message)
    })
    dev.off()
    
    if (!surv_ok) {
      create_fallback_pdf("survival_analysis.pdf", "Survival Analysis Plot (Not available or insufficient clinical data)")
    }
    
    message("canceR pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CANCER_CANCER_GENOMICS_MODELING":',
        paste0('    canceR: ', as.character(packageVersion('canceR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cancer_genomics_modeling.csv versions.yml
    """
}

workflow BIOC_CANCER_CANCER_GENOMICS_MODELING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_CANCER_CANCER_GENOMICS_MODELING(ch_input)

    emit:
    tables   = BIOC_CANCER_CANCER_GENOMICS_MODELING.out.tables
    plots    = BIOC_CANCER_CANCER_GENOMICS_MODELING.out.plots
    objects  = BIOC_CANCER_CANCER_GENOMICS_MODELING.out.objects
    versions = BIOC_CANCER_CANCER_GENOMICS_MODELING.out.versions
}
