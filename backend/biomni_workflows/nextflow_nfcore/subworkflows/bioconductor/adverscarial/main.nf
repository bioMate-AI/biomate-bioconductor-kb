#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: adverSCarial — single_gene_attack
// Identify and apply a single-gene perturbation that alters the cell-type classification of a target cell cluster.
// Input: counts_matrix.ext, cell_annotations.ext
// Container: quay.io/biocontainers/bioconductor-adverscarial:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DelayedArray, adverSCarial
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run a dichotomic search for single-gene attacks using advSingleGene
//  * 2. [Core Analysis] Apply the identified gene modification to the expression matrix using advModifications
//  * 3. [Core Analysis] Verify the successful misclassification using the classifier function

nextflow.enable.dsl = 2

process BIOC_ADVERSCARIAL_SINGLE_GENE_ATTACK {
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
    .bm_deps <- c("adverSCarial", "DelayedArray")
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
    library(DelayedArray)
    library(methods)
    
    # Helper function to find and read the counts matrix
    find_and_read_matrix <- function() {
      possible_files <- list.files(pattern = "^counts_matrix\\\\.")
      if (length(possible_files) == 0) {
        stop("Error: counts_matrix.ext not found in the working directory.")
      }
      file_path <- possible_files[1]
      ext <- tools::file_ext(file_path)
      
      if (ext == "rds") {
        mat <- readRDS(file_path)
      } else if (ext %in% c("csv", "txt", "tsv")) {
        sep <- ifelse(ext == "csv", ",", "\t")
        mat <- as.matrix(read.table(file_path, header = TRUE, sep = sep, row.names = 1, check.names = FALSE))
      } else {
        stop(paste("Error: Unsupported format for counts matrix:", ext))
      }
      
      return(DelayedArray::DelayedArray(mat))
    }
    
    # Helper function to find and read the cell annotations
    find_and_read_annotations <- function() {
      possible_files <- list.files(pattern = "^cell_annotations\\\\.")
      if (length(possible_files) == 0) {
        stop("Error: cell_annotations.ext not found in the working directory.")
      }
      file_path <- possible_files[1]
      ext <- tools::file_ext(file_path)
      
      if (ext == "rds") {
        vec <- readRDS(file_path)
      } else {
        vec <- readLines(file_path)
        if (grepl(",", vec[1]) || grepl("\t", vec[1])) {
          sep <- ifelse(grepl(",", vec[1]), ",", "\t")
          df <- read.table(file_path, header = TRUE, sep = sep, stringsAsFactors = FALSE)
          vec <- df[[1]]
        }
      }
      return(as.character(vec))
    }
    
    # 1. Load User Input Files
    matPbmc <- find_and_read_matrix()
    cellTypes <- find_and_read_annotations()
    
    # Dynamically select the target cluster (e.g., the first unique cluster)
    target_cluster <- unique(cellTypes)[1]
    
    # Define a generic centroid-based classifier to replace the dataset-specific MClassifier
    ref_centroids <- sapply(unique(cellTypes), function(cl) {
      rowMeans(matPbmc[, cellTypes == cl, drop = FALSE])
    })
    colnames(ref_centroids) <- unique(cellTypes)
    
    generic_classifier <- function(expr, clusters, target) {
      target_cells <- expr[, clusters == target, drop = FALSE]
      if (ncol(target_cells) == 0) {
        return(list(prediction = "UNDETERMINED", odd = 0))
      }
      target_mean <- rowMeans(target_cells)
      
      dists <- colSums((ref_centroids - target_mean)^2)
      predicted_class <- names(which.min(dists))
      odd <- as.numeric(1 / (1 + min(dists)))
      
      list(prediction = predicted_class, odd = odd)
    }
    
    # 2. Run a dichotomic search for single-gene attacks using advSingleGene
    genesMinChange <- advSingleGene(
      matPbmc, 
      cellTypes, 
      target_cluster, 
      generic_classifier, 
      exclGenes = character(0), 
      advMethod = "perc99", 
      returnFirstFound = TRUE, 
      changeType = "not_na", 
      firstDichot = 10
    )
    
    # Save the single-gene search results
    saveRDS(genesMinChange, "genes_min_change.rds")
    
    # Write a summary table of the identified single-gene attack
    if (length(genesMinChange@values) > 0) {
      summary_df <- data.frame(
        Gene = names(genesMinChange@values),
        Target_Classification = as.character(genesMinChange@values),
        stringsAsFactors = FALSE
      )
      write.csv(summary_df, "single_gene_attack_summary.csv", row.names = FALSE)
      
      # 3. Apply the identified gene modification to the expression matrix using advModifications
      matAdver <- advModifications(matPbmc, names(genesMinChange@values)[1], cellTypes, target_cluster)
      
      # Save the modified adversarial expression matrix
      saveRDS(matAdver, "adversarial_counts_matrix.rds")
      
      # 4. Verify the successful misclassification using the classifier function
      resClassif <- generic_classifier(matAdver, cellTypes, target_cluster)
      
      # Save the verification classification results
      saveRDS(resClassif, "classification_results.rds")
      
      # Write a text summary of the classification verification
      sink("classification_summary.txt")
      cat("=== SINGLE-GENE ATTACK VERIFICATION ===\n")
      cat("Original Target Cluster:", target_cluster, "\n")
      cat("Predicted Class after Attack:", resClassif\$prediction, "\n")
      cat("Prediction Confidence (Odd Score):", resClassif\$odd, "\n")
      sink()
    } else {
      sink("classification_summary.txt")
      cat("=== SINGLE-GENE ATTACK VERIFICATION ===\n")
      cat("Original Target Cluster:", target_cluster, "\n")
      cat("No vulnerable genes found.\n")
      sink()
    }

    writeLines(c(
        '"BIOC_ADVERSCARIAL_SINGLE_GENE_ATTACK":',
        paste0('    adverSCarial: ', as.character(packageVersion('adverSCarial')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_gene_attack.csv versions.yml
    """
}

workflow BIOC_ADVERSCARIAL_SINGLE_GENE_ATTACK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.ext, cell_annotations.ext ] ]

    main:
    BIOC_ADVERSCARIAL_SINGLE_GENE_ATTACK(ch_input)

    emit:
    tables   = BIOC_ADVERSCARIAL_SINGLE_GENE_ATTACK.out.tables
    plots    = BIOC_ADVERSCARIAL_SINGLE_GENE_ATTACK.out.plots
    objects  = BIOC_ADVERSCARIAL_SINGLE_GENE_ATTACK.out.objects
    versions = BIOC_ADVERSCARIAL_SINGLE_GENE_ATTACK.out.versions
}
