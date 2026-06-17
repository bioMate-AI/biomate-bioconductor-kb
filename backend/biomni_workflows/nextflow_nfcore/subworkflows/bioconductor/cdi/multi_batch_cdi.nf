#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CDI — multi_batch_cdi
// Select the optimal clustering label set for a multi-batch scRNA-seq dataset using CDI.
// Input: two_batch_matrix, two_batch_matrix_batch, two_batch_matrix_label_df, two_batch_matrix_celltype
// Container: quay.io/biocontainers/bioconductor-cdi:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CDI, ggplot2
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Select feature genes using feature_gene_selection with batch labels
//  * 2. [Core Analysis] Calculate cell size factors using size_factor
//  * 3. [Core Analysis] Calculate CDI for candidate labels using calculate_CDI with batch labels
//  * 4. [Core Analysis] (Optional) Calculate CDI for benchmark labels
//  * 5. [Visualization & Output] Visualize CDI values using CDI_lineplot
//  * 6. [Core Analysis] (Optional) Compare optimal labels with benchmark labels using contingency_heatmap

nextflow.enable.dsl = 2

process BIOC_CDI_MULTI_BATCH_CDI {
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
    .bm_deps <- c("CDI", "ggplot2")
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
        library(CDI)
        library(ggplot2)
        
        # Helper function to load inputs from the working directory
        load_input <- function(name, required = TRUE) {
          extensions <- c(".rds", ".csv", ".tsv", ".txt", "")
          for (ext in extensions) {
            file_path <- paste0(name, ext)
            if (file.exists(file_path)) {
              message("Loading ", name, " from ", file_path)
              if (grepl("\\\\.rds\$", file_path)) {
                return(readRDS(file_path))
              } else if (grepl("\\\\.(csv|tsv|txt)\$", file_path)) {
                sep <- if (grepl("\\\\.csv\$", file_path)) "," else "\t"
                df <- tryCatch({
                  read.table(file_path, header = TRUE, sep = sep, row.names = 1, check.names = FALSE)
                }, error = function(e) {
                  read.table(file_path, header = TRUE, sep = sep, check.names = FALSE)
                })
                return(df)
              } else {
                return(tryCatch(readRDS(file_path), error = function(e) NULL))
              }
            }
          }
          if (required) {
            stop("Required input file '", name, "' not found in the working directory.")
          }
          return(NULL)
        }
        
        # Read user inputs
        two_batch_matrix <- load_input("two_batch_matrix", required = TRUE)
        two_batch_matrix_batch <- load_input("two_batch_matrix_batch", required = TRUE)
        two_batch_matrix_label_df <- load_input("two_batch_matrix_label_df", required = TRUE)
        two_batch_matrix_celltype <- load_input("two_batch_matrix_celltype", required = FALSE)
        
        # Ensure correct data types
        if (is.data.frame(two_batch_matrix)) {
          two_batch_matrix <- as.matrix(two_batch_matrix)
        }
        
        if (is.data.frame(two_batch_matrix_batch)) {
          two_batch_matrix_batch <- as.vector(unlist(two_batch_matrix_batch))
        } else if (is.factor(two_batch_matrix_batch)) {
          two_batch_matrix_batch <- as.character(two_batch_matrix_batch)
        }
        
        if (!is.data.frame(two_batch_matrix_label_df)) {
          two_batch_matrix_label_df <- as.data.frame(two_batch_matrix_label_df)
        }
        
        if (!is.null(two_batch_matrix_celltype)) {
          if (is.data.frame(two_batch_matrix_celltype)) {
            two_batch_matrix_celltype <- as.vector(unlist(two_batch_matrix_celltype))
          } else if (is.factor(two_batch_matrix_celltype)) {
            two_batch_matrix_celltype <- as.character(two_batch_matrix_celltype)
          }
        }
        
        # Create alias to handle vignette typo gracefully
        one_batch_matrix_label_df <- two_batch_matrix_label_df
        
        # 1. Select feature genes using feature_gene_selection with batch labels
        feature_gene_indx <- feature_gene_selection(
        	X = two_batch_matrix,
        	batch_label = two_batch_matrix_batch,
        	method = "wds",
        	nfeature = 500)
        sub_two_batch_matrix <- two_batch_matrix[feature_gene_indx,]
        
        # Save selected feature matrix
        saveRDS(sub_two_batch_matrix, "selected_feature_matrix.rds")
        
        # 2. Calculate cell size factors using size_factor
        two_batch_matrix_size_factor <- size_factor(two_batch_matrix)
        saveRDS(two_batch_matrix_size_factor, "size_factors.rds")
        
        # 3. Calculate CDI for candidate labels using calculate_CDI with batch labels
        start_time <- Sys.time()
        CDI_return2 <- calculate_CDI(
        	X = sub_two_batch_matrix,
        	cand_lab_df = two_batch_matrix_label_df, 
        	batch_label = two_batch_matrix_batch,
        	cell_size_factor = two_batch_matrix_size_factor)
        end_time <- Sys.time()
        print(difftime(end_time, start_time))
        
        # Save CDI results
        write.csv(CDI_return2, "CDI_results.csv", row.names = TRUE)
        saveRDS(CDI_return2, "CDI_results.rds")
        
        # 4. (Optional) Calculate CDI for benchmark labels
        benchmark_return <- NULL
        if (!is.null(two_batch_matrix_celltype)) {
          tryCatch({
            benchmark_return <- calculate_CDI(
        	X = sub_two_batch_matrix,
        	cand_lab_df = two_batch_matrix_celltype,
        	batch_label = two_batch_matrix_batch,
        	cell_size_factor = two_batch_matrix_size_factor)
            write.csv(benchmark_return, "benchmark_CDI_results.csv", row.names = TRUE)
          }, error = function(e) {
            warning("Failed to calculate benchmark CDI: ", e\$message)
          })
        }
        
        # 5. Visualize CDI values using CDI_lineplot
        tryCatch({
          pdf("CDI_lineplot.pdf", width = 8, height = 6)
          if (!is.null(benchmark_return)) {
            p <- CDI_lineplot(cdi_dataframe = CDI_return2,
        	cdi_type = "CDI_BIC",
        	benchmark_celltype_cdi = benchmark_return,
        	benchmark_celltype_ncluster = length(unique(two_batch_matrix_celltype))) 
          } else {
            p <- CDI_lineplot(cdi_dataframe = CDI_return2,
        	cdi_type = "CDI_BIC")
          }
          print(p)
          dev.off()
        }, error = function(e) {
          warning("Failed to generate CDI lineplot: ", e\$message)
          if (dev.cur() > 1) dev.off()
        })
        
        # 6. (Optional) Compare optimal labels with benchmark labels using contingency_heatmap
        if (!is.null(two_batch_matrix_celltype)) {
          tryCatch({
            optimal_label_name <- CDI_return2\$Label_name[which.min(CDI_return2\$CDI_BIC)]
            optimal_label <- two_batch_matrix_label_df[[optimal_label_name]]
            
            pdf("contingency_heatmap.pdf", width = 8, height = 6)
            p <- contingency_heatmap(
        	benchmark_label = two_batch_matrix_celltype,
        	candidate_label = optimal_label,
        	rename_candidate_clusters = TRUE,
        	candidate_cluster_names = paste0('cluster', seq_len(length(unique(optimal_label)))))
            print(p)
            dev.off()
          }, error = function(e) {
            warning("Failed to generate contingency heatmap: ", e\$message)
            if (dev.cur() > 1) dev.off()
          })
        }
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CDI_MULTI_BATCH_CDI":',
        paste0('    CDI: ', as.character(packageVersion('CDI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_batch_cdi.csv versions.yml
    """
}

workflow BIOC_CDI_MULTI_BATCH_CDI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ two_batch_matrix, two_batch_matrix_batch, two_batch_matrix_label_df, two_batch_matrix_celltype ] ]

    main:
    BIOC_CDI_MULTI_BATCH_CDI(ch_input)

    emit:
    tables   = BIOC_CDI_MULTI_BATCH_CDI.out.tables
    plots    = BIOC_CDI_MULTI_BATCH_CDI.out.plots
    objects  = BIOC_CDI_MULTI_BATCH_CDI.out.objects
    versions = BIOC_CDI_MULTI_BATCH_CDI.out.versions
}
