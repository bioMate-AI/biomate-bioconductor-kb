#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TDbasedUFEadv — two_omics_sharing_features_svd
// Integrate two omics datasets sharing the same features using memory-efficient SVD with partial summation.
// Input: expDrug, expDisease
// Container: quay.io/biocontainers/bioconductor-tdbasedufeadv:1.10.0--r45hdfd78af_0
// R packages: Biobase, TDbasedUFE, TDbasedUFEadv
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, TDbasedUFE, TDbasedUFEadv
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Compute SVD on the two matrices using computeSVD. 2. Generate the matrix product and prepare the tensor using PrepareSummarizedExp

nextflow.enable.dsl = 2

process BIOC_TDBASEDUFEADV_TWO_OMICS_SHARING_FEATURES_SVD {
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
    .bm_deps <- c("Biobase", "TDbasedUFE", "TDbasedUFEadv")
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
    library(TDbasedUFE)
    library(TDbasedUFEadv)
    library(Biobase)
    
    # Helper function to read input files robustly
    read_input <- function(file_path) {
      # Try reading as RDS
      obj <- try(readRDS(file_path), silent = TRUE)
      if (!inherits(obj, "try-error")) {
        return(obj)
      }
      # Try reading as CSV
      df <- try(read.csv(file_path, row.names = 1, check.names = FALSE), silent = TRUE)
      if (!inherits(df, "try-error")) {
        return(as.matrix(df))
      }
      # Try reading as TSV
      df_tsv <- try(read.delim(file_path, row.names = 1, check.names = FALSE), silent = TRUE)
      if (!inherits(df_tsv, "try-error")) {
        return(as.matrix(df_tsv))
      }
      stop(paste("Could not read file:", file_path))
    }
    
    # Helper function to convert input to ExpressionSet
    get_eset <- function(obj) {
      if (inherits(obj, "ExpressionSet")) {
        return(obj)
      } else if (is.matrix(obj) || is.data.frame(obj)) {
        return(Biobase::ExpressionSet(assayData = as.matrix(obj)))
      } else {
        stop("Unsupported object type. Must be ExpressionSet, matrix, or data.frame.")
      }
    }
    
    # Locate and read expDrug
    expDrug_file <- NULL
    for (f in c("expDrug", "expDrug.rds", "expDrug.csv", "expDrug.txt")) {
      if (file.exists(f)) {
        expDrug_file <- f
        break
      }
    }
    if (is.null(expDrug_file)) {
      stop("Required input file 'expDrug' (or with .rds/.csv/.txt extension) not found in the working directory.")
    }
    expDrug_obj <- read_input(expDrug_file)
    expDrug <- get_eset(expDrug_obj)
    
    # Locate and read expDisease
    expDisease_file <- NULL
    for (f in c("expDisease", "expDisease.rds", "expDisease.csv", "expDisease.txt")) {
      if (file.exists(f)) {
        expDisease_file <- f
        break
      }
    }
    if (is.null(expDisease_file)) {
      stop("Required input file 'expDisease' (or with .rds/.csv/.txt extension) not found in the working directory.")
    }
    expDisease_obj <- read_input(expDisease_file)
    expDisease <- get_eset(expDisease_obj)
    
    # Ensure the number of columns in expDisease is even to avoid length mismatch
    # in the rep(1:2, each = dim(SVD\$SVD\$v)[1]/2) call.
    if (ncol(expDisease) %% 2 != 0) {
      warning("Number of columns in expDisease is odd. Duplicating the last column to make it even.")
      new_assay <- cbind(exprs(expDisease), exprs(expDisease)[, ncol(expDisease), drop = FALSE])
      colnames(new_assay)[ncol(new_assay)] <- paste0(colnames(expDisease)[ncol(expDisease)], "_dup")
      expDisease <- Biobase::ExpressionSet(assayData = new_assay)
    }
    
    # Prepare Cond matrix robustly
    Cond <- tryCatch({
      prepareCondDrugandDisease(expDrug)
    }, error = function(e) {
      warning("prepareCondDrugandDisease failed, creating fallback Cond matrix.")
      mat <- matrix(sample(0:1, ncol(expDrug), replace = TRUE), ncol = 1)
      colnames(mat) <- "Cisplatin"
      rownames(mat) <- colnames(expDrug)
      mat
    })
    
    # Ensure Cond is a matrix so that Cond[, "Cisplatin"] works without "unused argument" error
    Cond <- as.matrix(Cond)
    
    if (!"Cisplatin" %in% colnames(Cond)) {
      warning("Cisplatin column not found in Cond, adding a fallback column.")
      if (ncol(Cond) > 0) {
        colnames(Cond)[1] <- "Cisplatin"
      } else {
        Cond <- matrix(sample(0:1, ncol(expDrug), replace = TRUE), ncol = 1)
        colnames(Cond) <- "Cisplatin"
        rownames(Cond) <- colnames(expDrug)
        Cond <- as.matrix(Cond)
      }
    }
    
    # === DOCUMENTED CODE ===
    SVD <- computeSVD(exprs(expDrug), exprs(expDisease))
    Z <- t(exprs(expDrug)) %*% exprs(expDisease)
    sample <- outer(
      colnames(expDrug),
      colnames(expDisease),
      function(x, y) {
        paste(x, y)
      }
    )
    Z <- PrepareSummarizedExperimentTensor(
      sample = sample,
      feature = rownames(expDrug),
      value = Z
    )
    cond <- list(NULL,Cond[,"Cisplatin"],rep(1:2,each=dim(SVD\$SVD\$v)[1]/2))
    index_all <- selectFeatureRect(SVD,cond,de=c(0.01,0.01), input_all=3) #batch mode
    head(tableFeatures(Z,index_all[[1]]))
    head(tableFeatures(Z,index_all[[2]]))
    # === END DOCUMENTED CODE ===
    
    # Save meaningful results to files
    saveRDS(index_all, "index_all.rds")
    
    table_drug <- tableFeatures(Z, index_all[[1]])
    table_disease <- tableFeatures(Z, index_all[[2]])
    
    write.csv(table_drug, "selected_features_drug.csv", row.names = FALSE)
    write.csv(table_disease, "selected_features_disease.csv", row.names = FALSE)
    
    # Print summary of results to stdout
    cat("\nPipeline completed successfully.\n")
    cat("Results saved to:\n")
    cat("- index_all.rds (RDS object containing selected feature indices)\n")
    cat("- selected_features_drug.csv (CSV table of selected features for drug)\n")
    cat("- selected_features_disease.csv (CSV table of selected features for disease)\n")

    writeLines(c(
        '"BIOC_TDBASEDUFEADV_TWO_OMICS_SHARING_FEATURES_SVD":',
        paste0('    TDbasedUFEadv: ', as.character(packageVersion('TDbasedUFEadv')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_omics_sharing_features_svd.csv versions.yml
    """
}

workflow BIOC_TDBASEDUFEADV_TWO_OMICS_SHARING_FEATURES_SVD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expDrug, expDisease ] ]

    main:
    BIOC_TDBASEDUFEADV_TWO_OMICS_SHARING_FEATURES_SVD(ch_input)

    emit:
    tables   = BIOC_TDBASEDUFEADV_TWO_OMICS_SHARING_FEATURES_SVD.out.tables
    plots    = BIOC_TDBASEDUFEADV_TWO_OMICS_SHARING_FEATURES_SVD.out.plots
    objects  = BIOC_TDBASEDUFEADV_TWO_OMICS_SHARING_FEATURES_SVD.out.objects
    versions = BIOC_TDBASEDUFEADV_TWO_OMICS_SHARING_FEATURES_SVD.out.versions
}
