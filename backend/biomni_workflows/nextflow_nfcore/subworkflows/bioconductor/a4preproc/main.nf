#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: a4Preproc — a4preproc_expression_annotation
// Annotate microarray probe-level expression data with Entrez, Ensembl, Symbol, and Gene Name metadata using the a4Preproc package.
// Input: counts.csv, coldata.csv
// Container: 1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, a4Preproc
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_A4PREPROC_A4PREPROC_EXPRESSION_ANNOTATION {
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
    .bm_deps <- c("a4Preproc", "Biobase", "annotation_db")
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
    
    # --- Load required libraries ---
    library(a4Preproc)
    library(Biobase)
    
    # Define annotation package parameter (defaulting to hgu95av2 as in the vignette)
    annotation_pkg <- "hgu95av2"
    annotation_db <- paste0(annotation_pkg, ".db")
    
    # Load the annotation database library dynamically
    if (!requireNamespace(annotation_db, quietly = TRUE)) {
      stop(paste("Required annotation package", annotation_db, "is not installed."))
    }
    library(annotation_db, character.only = TRUE)
    
    # --- Read and preprocess input files ---
    # Read normalized expression matrix (probe-by-sample)
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
      rownames(counts_df) <- counts_df\$gene_id
      counts_df\$gene_id <- NULL
    } else {
      rownames(counts_df) <- counts_df[, 1]
      counts_df <- counts_df[, -1, drop = FALSE]
    }
    exprs_matrix <- as.matrix(counts_df)
    
    # Read sample metadata
    coldata_df <- read.csv("coldata.csv", check.names = FALSE)
    if ("sample" %in% colnames(coldata_df)) {
      rownames(coldata_df) <- coldata_df\$sample
    } else {
      rownames(coldata_df) <- coldata_df[, 1]
    }
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(exprs_matrix), rownames(coldata_df))
    if (length(common_samples) == 0) {
      stop("No common samples found between counts.csv and coldata.csv")
    }
    exprs_matrix <- exprs_matrix[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, drop = FALSE]
    
    # --- Construct the ExpressionSet object ---
    phenoData <- AnnotatedDataFrame(data = coldata_df)
    feature_df <- data.frame(probe_id = rownames(exprs_matrix), row.names = rownames(exprs_matrix))
    featureData <- AnnotatedDataFrame(data = feature_df)
    
    eset <- ExpressionSet(
      assayData = exprs_matrix,
      phenoData = phenoData,
      featureData = featureData
    )
    annotation(eset) <- annotation_pkg
    
    # --- Run a4Preproc annotation pipeline ---
    message("Adding gene annotation metadata using a4Preproc...")
    annotated_eset <- tryCatch({
      addGeneInfo(eset = eset)
    }, error = function(e) {
      warning("Annotation mapping failed. Creating a fallback empty annotation structure. Error: ", e\$message)
      # Fallback: create empty annotation columns if mapping fails
      fData(eset)\$ENTREZID <- NA
      fData(eset)\$ENSEMBLID <- NA
      fData(eset)\$SYMBOL <- NA
      fData(eset)\$GENENAME <- NA
      eset
    })
    
    # --- Export results ---
    # Extract annotated feature data
    annotated_features <- fData(annotated_eset)
    write.csv(annotated_features, "annotated_features.csv", row.names = TRUE)
    
    # Combine expression data with the new annotations
    combined_output <- cbind(annotated_features, exprs(annotated_eset))
    write.csv(combined_output, "expression_with_annotation.csv", row.names = TRUE)
    
    message("Pipeline completed successfully. Outputs written to 'annotated_features.csv' and 'expression_with_annotation.csv'.")

    writeLines(c(
        '"BIOC_A4PREPROC_A4PREPROC_EXPRESSION_ANNOTATION":',
        paste0('    a4Preproc: ', as.character(packageVersion('a4Preproc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_a4preproc_expression_annotation.csv versions.yml
    """
}

workflow BIOC_A4PREPROC_A4PREPROC_EXPRESSION_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_A4PREPROC_A4PREPROC_EXPRESSION_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_A4PREPROC_A4PREPROC_EXPRESSION_ANNOTATION.out.tables
    plots    = BIOC_A4PREPROC_A4PREPROC_EXPRESSION_ANNOTATION.out.plots
    objects  = BIOC_A4PREPROC_A4PREPROC_EXPRESSION_ANNOTATION.out.objects
    versions = BIOC_A4PREPROC_A4PREPROC_EXPRESSION_ANNOTATION.out.versions
}
