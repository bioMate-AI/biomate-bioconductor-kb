#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: adverSCarial — cluster_gradient_descent_attack
// Apply a gradient-based Cluster Gradient Descent (CGD) attack to modify genes step-by-step until the cluster classification switches.
// Input: counts_matrix.ext, cell_annotations.ext
// Container: quay.io/biocontainers/bioconductor-adverscarial:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: adverSCarial
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the gradient descent attack using advCGD
//  * 2. [Core Analysis] Retrieve the modified expression matrix from the results
//  * 3. [Core Analysis] Verify the new classification of the modified matrix

nextflow.enable.dsl = 2

process BIOC_ADVERSCARIAL_CLUSTER_GRADIENT_DESCENT_ATTACK {
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
    .bm_deps <- c("adverSCarial")
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
    library(adverSCarial)
    
    # Helper function to read the counts matrix robustly
    read_input_matrix <- function(path) {
      if (!file.exists(path)) {
        base_name <- tools::file_path_sans_ext(basename(path))
        actual_files <- list.files(pattern = paste0("^", base_name, "\\\\."))
        if (length(actual_files) > 0) {
          path <- actual_files[1]
        } else {
          stop(paste("Input file not found:", path))
        }
      }
      
      ext <- tolower(tools::file_ext(path))
      if (ext == "rds") {
        return(readRDS(path))
      }
      
      tryCatch({
        return(as.matrix(read.table(path, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)))
      }, error = function(e) {
        tryCatch({
          return(as.matrix(read.csv(path, header = TRUE, row.names = 1, check.names = FALSE)))
        }, error = function(e2) {
          stop(paste("Failed to read matrix from", path))
        })
      })
    }
    
    # Helper function to read cell annotations robustly
    read_input_annotations <- function(path) {
      if (!file.exists(path)) {
        base_name <- tools::file_path_sans_ext(basename(path))
        actual_files <- list.files(pattern = paste0("^", base_name, "\\\\."))
        if (length(actual_files) > 0) {
          path <- actual_files[1]
        } else {
          stop(paste("Input file not found:", path))
        }
      }
      
      ext <- tolower(tools::file_ext(path))
      if (ext == "rds") {
        return(readRDS(path))
      }
      
      tryCatch({
        ann <- readLines(path)
        if (length(ann) > 0 && (ann[1] == "cell_type" || ann[1] == "x" || ann[1] == "cellTypes")) {
          ann <- ann[-1]
        }
        return(ann)
      }, error = function(e) {
        stop(paste("Failed to read annotations from", path))
      })
    }
    
    # 1. Load User Inputs
    matPbmc <- read_input_matrix("counts_matrix.ext")
    cellTypes <- read_input_annotations("cell_annotations.ext")
    cellTypes <- as.character(cellTypes)
    
    # Fix 2: Transpose if matrix has genes as rows and cells as columns
    if (ncol(matPbmc) == length(cellTypes) && nrow(matPbmc) != length(cellTypes)) {
      matPbmc <- t(matPbmc)
    }
    
    if (is.null(colnames(matPbmc))) {
      stop("Counts matrix must have gene names as column names.")
    }
    
    # Fix 1: Dynamically select a target cluster instead of hardcoding 'Memory CD4 T'
    # We select the most abundant cell type to ensure there are enough cells to attack
    target_cluster <- names(sort(table(cellTypes), decreasing = TRUE))[1]
    
    # Fix 3: Create a custom classifier instead of using the PBMC3k-specific MClassifier
    # We use a simple Nearest Centroid classifier based on the original data
    centroids <- matrix(0, nrow = length(unique(cellTypes)), ncol = ncol(matPbmc))
    rownames(centroids) <- unique(cellTypes)
    colnames(centroids) <- colnames(matPbmc)
    for (ct in unique(cellTypes)) {
      centroids[ct, ] <- colMeans(matPbmc[cellTypes == ct, , drop = FALSE], na.rm = TRUE)
    }
    
    custom_classifier <- function(expr, clusters, target) {
      expr_mat <- as.matrix(expr)
      scores <- matrix(0, nrow = nrow(centroids), ncol = nrow(expr_mat))
      rownames(scores) <- rownames(centroids)
      colnames(scores) <- rownames(expr_mat)
      
      for (ct in rownames(centroids)) {
        # Negative squared Euclidean distance as likelihood score
        diffs <- sweep(expr_mat, 2, centroids[ct, ], "-")
        scores[ct, ] <- -rowSums(diffs^2)
      }
      
      pred_cells <- rownames(scores)[apply(scores, 2, which.max)]
      names(pred_cells) <- colnames(scores)
      
      target_preds <- pred_cells[clusters == target]
      if (length(target_preds) == 0) {
        return(list(prediction = "UNDETERMINED", odd = 1, typePredictions = scores, cellTypes = pred_cells))
      }
      
      tbl <- table(target_preds)
      pred_class <- names(sort(tbl, decreasing = TRUE))[1]
      odd_val <- as.numeric(max(tbl) / sum(tbl))
      
      list(
        prediction = pred_class,
        odd = odd_val,
        typePredictions = scores,
        cellTypes = pred_cells
      )
    }
    
    # 2. Run the gradient descent attack using advCGD
    resCGD <- advCGD(as.data.frame(matPbmc), cellTypes, target_cluster, custom_classifier, alpha=1, epsilon=1, genes=colnames(matPbmc)[ncol(matPbmc):1])
    
    # 3. Retrieve the modified expression matrix from the results
    modifiedMatrix <- resCGD\$expr
    
    # 4. Verify the new classification of the modified matrix
    prediction_val <- custom_classifier(modifiedMatrix, cellTypes, target_cluster)\$prediction
    
    # 5. Save meaningful results to output files
    saveRDS(resCGD, "resCGD.rds")
    write.csv(as.data.frame(modifiedMatrix), "modified_counts_matrix.csv", row.names = TRUE)
    writeLines(as.character(prediction_val), "prediction_result.txt")
    
    if (!is.null(resCGD\$byGeneSummary)) {
      write.csv(resCGD\$byGeneSummary, "by_gene_summary.csv", row.names = FALSE)
    }
    if (!is.null(resCGD\$modGenes)) {
      writeLines(resCGD\$modGenes, "modified_genes.txt")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_ADVERSCARIAL_CLUSTER_GRADIENT_DESCENT_ATTACK":',
        paste0('    adverSCarial: ', as.character(packageVersion('adverSCarial')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cluster_gradient_descent_attack.csv versions.yml
    """
}

workflow BIOC_ADVERSCARIAL_CLUSTER_GRADIENT_DESCENT_ATTACK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.ext, cell_annotations.ext ] ]

    main:
    BIOC_ADVERSCARIAL_CLUSTER_GRADIENT_DESCENT_ATTACK(ch_input)

    emit:
    tables   = BIOC_ADVERSCARIAL_CLUSTER_GRADIENT_DESCENT_ATTACK.out.tables
    plots    = BIOC_ADVERSCARIAL_CLUSTER_GRADIENT_DESCENT_ATTACK.out.plots
    objects  = BIOC_ADVERSCARIAL_CLUSTER_GRADIENT_DESCENT_ATTACK.out.objects
    versions = BIOC_ADVERSCARIAL_CLUSTER_GRADIENT_DESCENT_ATTACK.out.versions
}
