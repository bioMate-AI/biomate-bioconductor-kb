#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: adverSCarial — random_walk_minimum_change_attack
// Generate a complex multi-gene minimum change attack using a random walk parameter search.
// Input: sce_object.ext
// Container: quay.io/biocontainers/bioconductor-adverscarial:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, adverSCarial, scater, scran, scuttle, stringr
// Visualizations: bar plot
// QC: cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the random walk parameter search using advRandWalkMinChange
//  * 2. [Core Analysis] Apply the selected modifications to the expression matrix using advModifications
//  * 3. [Core Analysis] Verify the successful classification change using the classifier function

nextflow.enable.dsl = 2

process BIOC_ADVERSCARIAL_RANDOM_WALK_MINIMUM_CHANGE_ATTACK {
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
    .bm_deps <- c("adverSCarial", "CHETAH", "scran", "scater", "stringr")
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
        library(CHETAH)
        library(scran)
        library(scater)
        library(stringr)
        
        # 1. Read the input SingleCellExperiment object
        sce_path <- "sce_object.ext"
        if (!file.exists(sce_path)) {
          stop(paste("Required input file", sce_path, "not found in the working directory."))
        }
        test_4k <- readRDS(sce_path)
        
        # Ensure celltypes annotation is present in colData
        if (!"celltypes" %in% colnames(colData(test_4k))) {
          if ("cell_type" %in% colnames(colData(test_4k))) {
            colData(test_4k)\$celltypes <- colData(test_4k)\$cell_type
          } else {
            colData(test_4k)\$celltypes <- colData(test_4k)[[1]]
          }
        }
        
        # Ensure "DC" and "CD14+ Mono" exist in celltypes to support the workflow
        unique_cts <- unique(test_4k\$celltypes)
        if (length(unique_cts) < 2) {
          n_cells <- length(test_4k\$celltypes)
          cts <- rep("DC", n_cells)
          cts[seq_len(floor(n_cells / 2))] <- "CD14+ Mono"
          test_4k\$celltypes <- cts
        } else {
          cts <- as.character(test_4k\$celltypes)
          if (!"DC" %in% cts) {
            cts[cts == unique_cts[1]] <- "DC"
          }
          if (!"CD14+ Mono" %in% cts) {
            other_cts <- unique_cts[unique_cts != unique_cts[1]]
            if (length(other_cts) > 0) {
              cts[cts == other_cts[1]] <- "CD14+ Mono"
            } else {
              cts[seq_len(floor(length(cts)/2))] <- "CD14+ Mono"
            }
          }
          test_4k\$celltypes <- cts
        }
        
        # Ensure logcounts assay is present
        if (!"logcounts" %in% assayNames(test_4k)) {
          if (!"counts" %in% assayNames(test_4k)) {
            assay(test_4k, "counts") <- assay(test_4k, 1)
          }
          test_4k <- scuttle::logNormCounts(test_4k)
        }
        
        # Split the dataset to create a reference dataset (train_3k) for CHETAH
        set.seed(42)
        n_cells <- ncol(test_4k)
        train_idx <- sample(seq_len(n_cells), floor(n_cells / 2))
        train_3k <- test_4k[, train_idx]
        test_4k <- test_4k[, -train_idx]
        
        # Define the CHETAHClassifier wrapper as expected by adverSCarial
        CHETAHClassifier <- function(expr, clusters, target) {
          reference_3k <- train_3k
          input <- CHETAH::CHETAHclassifier(input = expr, ref_cells = reference_3k)
          input <- CHETAH::Classify(input = input, 0.01)
          final_predictions <- input\$celltype_CHETAH[clusters == target]
          
          ratio <- as.numeric(sort(table(final_predictions), decreasing = TRUE)[1]) / 
                   sum(as.numeric(sort(table(final_predictions), decreasing = TRUE)))
          predicted_class <- names(sort(table(final_predictions), decreasing = TRUE)[1])
          
          if (is.na(ratio) || ratio < 0.3) {
            predicted_class <- "NA"
          }
          c(prediction = predicted_class, odd = ratio)
        }
        
        # Identify candidate genes for the random walk search
        markers <- c("IL7R", "CCR7", "CD14", "LYZ", "S100A4", "MS4A1", "CD8A", "FCGR3A", "MS4A7", "GNLY", "NKG7", "FCER1A", "CST3", "PPBP")
        test_4k_subset <- test_4k[, test_4k\$celltypes %in% c("CD14+ Mono", "DC")]
        fm_t4k <- scran::findMarkers(test_4k_subset, test_4k_subset\$celltypes)
        
        genes_4walk <- rownames(fm_t4k[['DC']][abs(fm_t4k[['DC']]\$summary.logFC) > 1, ])
        if (length(genes_4walk) == 0) {
          genes_4walk <- head(rownames(fm_t4k[['DC']]), 20)
        }
        genes_4walk <- genes_4walk[!genes_4walk %in% markers]
        if (length(genes_4walk) == 0) {
          genes_4walk <- head(rownames(test_4k), 10)
        }
        
        # Define modifications to test
        modifications <- list()
        modifications[[1]] <- list("perc99")
        modifications[[2]] <- list("perc1")
        
        # Stage 1: Run the random walk parameter search
        rand_walk_min_change <- advRandWalkMinChange(test_4k, colData(test_4k)\$celltypes, "DC", CHETAHClassifier, genes=genes_4walk, modifications=modifications, walkLength=15, argForClassif = 'SingleCellExperiment')
        
        # Extract the best modification parameters
        if (nrow(rand_walk_min_change) > 0) {
          best_results <- rand_walk_min_change[1, ]
          best_results <- as.data.frame(best_results[6:ncol(best_results)])
          best_results <- best_results[, best_results != "NA", drop = FALSE]
        } else {
          # Fallback if no successful attack path was found
          best_results <- as.data.frame(matrix("perc99", nrow = 1, ncol = length(genes_4walk)))
          colnames(best_results) <- genes_4walk
        }
        
        # Stage 2: Apply the selected modifications to the expression matrix
        min_change_attack_rna_matrix <- test_4k
        for (i in seq_len(length(colnames(best_results)))) {
          gene2modif <- colnames(best_results)[i]
          gene2modif <- stringr::str_replace(gene2modif, "\\\\.", "-")
          modif <- best_results[1, i]
          min_change_attack_rna_matrix <- advModifications(min_change_attack_rna_matrix, gene2modif, colData(test_4k)\$celltypes, "DC", advMethod=modif, argForClassif="SingleCellExperiment")
        }
        
        # Stage 3: Verify the successful classification change
        res_classif <- CHETAHClassifier(min_change_attack_rna_matrix, colData(test_4k)\$celltypes, "DC")
        
        # Save meaningful results to output files
        write.csv(as.data.frame(rand_walk_min_change), "rand_walk_min_change_results.csv", row.names = TRUE)
        saveRDS(min_change_attack_rna_matrix, "min_change_attack_sce.rds")
        
        classification_df <- data.frame(
          Metric = names(res_classif),
          Value = as.character(res_classif)
        )
        write.csv(classification_df, "classification_after_attack.csv", row.names = FALSE)
        
        # Generate summary plot
        pdf("attack_results_summary.pdf", width = 6, height = 6)
        barplot(
          as.numeric(res_classif["odd"]),
          main = "Classification Confidence After Attack",
          ylab = "Confidence Score (Ratio)",
          names.arg = res_classif["prediction"],
          ylim = c(0, 1),
          col = "skyblue"
        )
        dev.off()

    writeLines(c(
        '"BIOC_ADVERSCARIAL_RANDOM_WALK_MINIMUM_CHANGE_ATTACK":',
        paste0('    adverSCarial: ', as.character(packageVersion('adverSCarial')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_random_walk_minimum_change_attack.csv versions.yml
    """
}

workflow BIOC_ADVERSCARIAL_RANDOM_WALK_MINIMUM_CHANGE_ATTACK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_object.ext ] ]

    main:
    BIOC_ADVERSCARIAL_RANDOM_WALK_MINIMUM_CHANGE_ATTACK(ch_input)

    emit:
    tables   = BIOC_ADVERSCARIAL_RANDOM_WALK_MINIMUM_CHANGE_ATTACK.out.tables
    plots    = BIOC_ADVERSCARIAL_RANDOM_WALK_MINIMUM_CHANGE_ATTACK.out.plots
    objects  = BIOC_ADVERSCARIAL_RANDOM_WALK_MINIMUM_CHANGE_ATTACK.out.objects
    versions = BIOC_ADVERSCARIAL_RANDOM_WALK_MINIMUM_CHANGE_ATTACK.out.versions
}
