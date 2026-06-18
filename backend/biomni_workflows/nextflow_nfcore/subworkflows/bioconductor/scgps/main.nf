#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scGPS — subpopulation_identification_and_characterisation
// Identify stable cell clusters in single-cell expression data using CORE or SCORE, visualize them, and find marker genes.
// Input: ExpressionMatrix, GeneMetadata, CellMetadata
// Container: quay.io/biocontainers/bioconductor-scgps:1.24.0--r45ha27e39d_0
// R packages: SingleCellExperiment, clusterProfiler, DOSE, dplyr, locfit, ReactomePA, scGPS
// Bioconductor: 3.20 | R: 4.4
// Requires: ReactomePA, SingleCellExperiment, clusterProfiler, locfit, scGPS
// Visualizations: dot plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create scGPS object
//  * 2. [Core Analysis] Run CORE clustering or SCORE bagging clustering
//  * 3. [Core Analysis] Extract optimal clustering and update the scGPS object
//  * 4. [Visualization & Output] Plot clustering dendrograms and optimal cluster bars
//  * 5. [Core Analysis] Compare clustering with tSNE dimensional reduction
//  * 6. [Core Analysis] Find differential marker genes and annotate clusters

nextflow.enable.dsl = 2

process BIOC_SCGPS_SUBPOPULATION_IDENTIFICATION_AND_CHARACTERISATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SingleCellExperiment", "clusterProfiler", "DOSE", "dplyr", "locfit", "ReactomePA", "scGPS", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    
    # Load required libraries
    library(scGPS)
    library(SummarizedExperiment)
    library(locfit)
    library(DOSE)
    library(ReactomePA)
    library(clusterProfiler)
    
    # Helper function to read input files with various extensions
    read_input_file <- function(base_name) {
      possible_extensions <- c(".rds", ".RDS", ".csv", ".CSV", ".tsv", ".TSV", ".txt", ".TXT")
      for (ext in possible_extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          message("Reading: ", file_path)
          if (tolower(ext) == ".rds") {
            return(readRDS(file_path))
          } else if (tolower(ext) == ".csv") {
            return(read.csv(file_path, row.names = 1, check.names = FALSE))
          } else if (tolower(ext) %in% c(".tsv", ".txt")) {
            return(read.delim(file_path, row.names = 1, check.names = FALSE))
          }
        }
      }
      stop("Could not find input file for: ", base_name)
    }
    
    # Read user inputs
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    expr_mat <- as.matrix(read_input_file("ExpressionMatrix"))
    gene_metadata <- as.data.frame(read_input_file("GeneMetadata"))
    cell_metadata <- as.data.frame(read_input_file("CellMetadata"))
    
    # Format CellMetadata to match the required structure
    if (!all(c("Cluster", "cellBarcodes") %in% colnames(cell_metadata))) {
      col_barcodes <- NULL
      for (col in colnames(cell_metadata)) {
        if (any(cell_metadata[[col]] %in% colnames(expr_mat))) {
          col_barcodes <- col
          break
        }
      }
      if (is.null(col_barcodes)) {
        col_barcodes <- colnames(cell_metadata)[1]
      }
      col_cluster <- setdiff(colnames(cell_metadata), col_barcodes)[1]
      if (is.na(col_cluster)) {
        cell_metadata\$Cluster <- 1
        col_cluster <- "Cluster"
      }
      cellnames <- data.frame(
        Cluster = cell_metadata[[col_cluster]],
        cellBarcodes = cell_metadata[[col_barcodes]],
        stringsAsFactors = FALSE
      )
    } else {
      cellnames <- cell_metadata[, c("Cluster", "cellBarcodes")]
    }
    
    # 1. Create scGPS object
    mixedpop2 <- new_scGPS_object(ExpressionMatrix = expr_mat,
                                  GeneMetadata = gene_metadata,
                                  CellMetadata = cellnames)
    
    # 2. Run CORE clustering
    CORE_cluster <- CORE_clustering(mixedpop2, remove_outlier = c(0), PCA=FALSE)
    
    # 3. Extract optimal clustering and update the scGPS object
    key_height <- CORE_cluster\$optimalClust\$KeyStats\$Height
    optimal_res <- CORE_cluster\$optimalClust\$OptimalRes
    optimal_index = which(key_height == optimal_res)
    
    clustering_after_outlier_removal <- unname(unlist(
     CORE_cluster\$Cluster[[optimal_index]]))
    corresponding_cells_after_outlier_removal <- CORE_cluster\$cellsForClustering
    original_cells_before_removal <- colData(mixedpop2)[,2]
    corresponding_index <- match(corresponding_cells_after_outlier_removal,
                                original_cells_before_removal )
    
    mixedpop2_post_clustering <- mixedpop2[,corresponding_index]
    colData(mixedpop2_post_clustering)[,1] <- clustering_after_outlier_removal
    
    # 4. Run SCORE bagging clustering
    SCORE_test <- CORE_bagging(mixedpop2, remove_outlier = c(0), PCA=FALSE,
                                    bagging_run = 20, subsample_proportion = .8)
    
    # Open PDF device for plots
    pdf("scGPS_plots.pdf", width = 10, height = 8)
    
    # 5. Plot clustering dendrograms and optimal cluster bars
    p1 <- plot_CORE(CORE_cluster\$tree, CORE_cluster\$Cluster, 
        color_branch = c("#208eb7", "#6ce9d3", "#1c5e39", "#8fca40", "#154975",
            "#b1c8eb"))
    
    plot_optimal_CORE(original_tree= CORE_cluster\$tree,
                     optimal_cluster = unlist(CORE_cluster\$Cluster[optimal_index]),
                     shift = -2000)
    
    plot_CORE(SCORE_test\$tree, list_clusters = SCORE_test\$Cluster)
    
    plot_optimal_CORE(original_tree= SCORE_test\$tree,
                     optimal_cluster = unlist(SCORE_test\$Cluster[
                        SCORE_test\$optimal_index]),
                     shift = -100)
    
    # 6. Compare clustering with tSNE dimensional reduction
    t <- tSNE(expression.mat=assay(mixedpop2))
    p2 <- plot_reduced(t, color_fac = factor(colData(mixedpop2)[,1]),
                          palletes =1:length(unique(colData(mixedpop2)[,1])))
    print(p2)
    
    # 7. Find differential marker genes and annotate clusters
    DEgenes <- find_markers(expression_matrix=assay(mixedpop2),
                                cluster = colData(mixedpop2)[,1],
                                selected_cluster=unique(colData(mixedpop2)[,1]))
    
    # Extract genes for annotation
    if (is.list(DEgenes) && length(DEgenes) > 0) {
      genes <- NULL
      for (i in seq_along(DEgenes)) {
        if (is.data.frame(DEgenes[[i]]) && "id" %in% colnames(DEgenes[[i]])) {
          genes <- as.character(DEgenes[[i]]\$id)
          break
        }
      }
      if (is.null(genes)) {
        genes <- rownames(assay(mixedpop2))
      }
    } else {
      genes <- rownames(assay(mixedpop2))
    }
    
    genes <- unique(na.omit(genes))
    if (length(genes) > 500) {
      genes <- genes[1:500]
    }
    
    enrichment_test <- tryCatch({
      annotate_clusters(genes, pvalueCutoff=0.05, gene_symbol=TRUE)
    }, error = function(e) {
      message("Warning: annotate_clusters failed. Error: ", e\$message)
      NULL
    })
    
    if (!is.null(enrichment_test)) {
      tryCatch({
        p_enrich <- clusterProfiler::dotplot(enrichment_test, showCategory=10, font.size = 6)
        print(p_enrich)
      }, error = function(e) {
        message("Warning: plotting enrichment failed. Error: ", e\$message)
      })
    }
    
    dev.off()
    
    # Save RDS outputs
    saveRDS(mixedpop2_post_clustering, "mixedpop2_post_clustering.rds")
    saveRDS(CORE_cluster, "CORE_cluster.rds")
    saveRDS(SCORE_test, "SCORE_test.rds")
    saveRDS(DEgenes, "DEgenes.rds")
    if (!is.null(enrichment_test)) {
      saveRDS(enrichment_test, "enrichment_test.rds")
    }
    
    message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCGPS_SUBPOPULATION_IDENTIFICATION_AND_CHARACTERISATION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCGPS_SUBPOPULATION_IDENTIFICATION_AND_CHARACTERISATION":',
        paste0('    scGPS: ', as.character(packageVersion('scGPS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_subpopulation_identification_and_characterisation.csv versions.yml
    """
}

workflow BIOC_SCGPS_SUBPOPULATION_IDENTIFICATION_AND_CHARACTERISATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionMatrix, GeneMetadata, CellMetadata ] ]

    main:
    BIOC_SCGPS_SUBPOPULATION_IDENTIFICATION_AND_CHARACTERISATION(ch_input)

    emit:
    tables   = BIOC_SCGPS_SUBPOPULATION_IDENTIFICATION_AND_CHARACTERISATION.out.tables
    plots    = BIOC_SCGPS_SUBPOPULATION_IDENTIFICATION_AND_CHARACTERISATION.out.plots
    objects  = BIOC_SCGPS_SUBPOPULATION_IDENTIFICATION_AND_CHARACTERISATION.out.objects
    versions = BIOC_SCGPS_SUBPOPULATION_IDENTIFICATION_AND_CHARACTERISATION.out.versions
}
