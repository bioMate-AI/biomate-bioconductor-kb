#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CDI — single_batch_cdi
// Select the optimal clustering label set for a single-batch scRNA-seq dataset using CDI.
// Input: one_batch_matrix, one_batch_matrix_label_df, one_batch_matrix_celltype
// Container: quay.io/biocontainers/bioconductor-cdi:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CDI
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Select feature genes using feature_gene_selection
//  * 2. [Core Analysis] Calculate cell size factors using size_factor
//  * 3. [Core Analysis] Calculate CDI for candidate labels using calculate_CDI
//  * 4. [Visualization & Output] Visualize CDI values using CDI_lineplot
//  * 5. [Core Analysis] (Optional) Compare optimal labels with benchmark labels using contingency_heatmap
//  * 6. [Core Analysis] (Optional) Calculate CDI for benchmark labels and add to the lineplot

nextflow.enable.dsl = 2

process BIOC_CDI_SINGLE_BATCH_CDI {
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
    .bm_deps <- c("CDI")
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
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        
        # Read one_batch_matrix (raw UMI count matrix)
        if (file.exists("one_batch_matrix.rds")) {
          one_batch_matrix <- readRDS("one_batch_matrix.rds")
        } else if (file.exists("one_batch_matrix.csv")) {
          one_batch_matrix <- as.matrix(read.csv("one_batch_matrix.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("one_batch_matrix.tsv")) {
          one_batch_matrix <- as.matrix(read.delim("one_batch_matrix.tsv", row.names = 1, check.names = FALSE))
        } else {
          stop("Error: one_batch_matrix not found in the working directory (expected .rds, .csv, or .tsv)")
        }
        
        # Read one_batch_matrix_label_df (data frame of candidate cell labels)
        if (file.exists("one_batch_matrix_label_df.rds")) {
          one_batch_matrix_label_df <- readRDS("one_batch_matrix_label_df.rds")
        } else if (file.exists("one_batch_matrix_label_df.csv")) {
          one_batch_matrix_label_df <- read.csv("one_batch_matrix_label_df.csv", row.names = 1, check.names = FALSE)
        } else if (file.exists("one_batch_matrix_label_df.tsv")) {
          one_batch_matrix_label_df <- read.delim("one_batch_matrix_label_df.tsv", row.names = 1, check.names = FALSE)
        } else {
          stop("Error: one_batch_matrix_label_df not found in the working directory (expected .rds, .csv, or .tsv)")
        }
        
        # Read one_batch_matrix_celltype (optional vector of benchmark cell types)
        one_batch_matrix_celltype <- NULL
        if (file.exists("one_batch_matrix_celltype.rds")) {
          one_batch_matrix_celltype <- readRDS("one_batch_matrix_celltype.rds")
        } else if (file.exists("one_batch_matrix_celltype.csv")) {
          one_batch_matrix_celltype_df <- read.csv("one_batch_matrix_celltype.csv", header = FALSE)
          one_batch_matrix_celltype <- as.character(one_batch_matrix_celltype_df[[1]])
        } else if (file.exists("one_batch_matrix_celltype.tsv")) {
          one_batch_matrix_celltype_df <- read.delim("one_batch_matrix_celltype.tsv", header = FALSE)
          one_batch_matrix_celltype <- as.character(one_batch_matrix_celltype_df[[1]])
        } else if (file.exists("one_batch_matrix_celltype.txt")) {
          one_batch_matrix_celltype <- readLines("one_batch_matrix_celltype.txt")
        }
        
        # ==========================================
        # 2. Execute CDI Workflow
        # ==========================================
        
        # Step 1: Select feature genes using feature_gene_selection
        feature_gene_indx <- feature_gene_selection(
        	X = one_batch_matrix, 
        	batch_label = NULL, 
        	method = "wds", 
        	nfeature = 500)
        sub_one_batch_matrix <- one_batch_matrix[feature_gene_indx,]
        
        # Step 2: Calculate cell size factors using size_factor
        one_batch_matrix_size_factor <- size_factor(X = one_batch_matrix)
        
        # Step 3: Calculate CDI for candidate labels using calculate_CDI
        start_time <- Sys.time()
        CDI_return1 <- calculate_CDI(
        	X = sub_one_batch_matrix, 
        	cand_lab_df = one_batch_matrix_label_df, 
        	batch_label = NULL, 
        	cell_size_factor = one_batch_matrix_size_factor)
        end_time <- Sys.time()
        print(difftime(end_time, start_time))
        
        # Save CDI results table
        write.csv(CDI_return1, "CDI_results.csv", row.names = FALSE)
        
        # Step 4: Visualize CDI values using CDI_lineplot
        pdf("CDI_lineplot_BIC.pdf")
        print(CDI_lineplot(cdi_dataframe = CDI_return1, cdi_type = "CDI_BIC"))
        dev.off()
        
        # Step 5 & 6: Optional Benchmark Comparison (if benchmark cell types are provided)
        if (!is.null(one_batch_matrix_celltype)) {
          
          # Compare optimal labels with benchmark labels using contingency_heatmap
          # Wrapped in tryCatch in case the optimal label is not present or incompatible
          tryCatch({
            optimal_label_name <- CDI_return1\$Label_name[which.min(CDI_return1\$CDI_BIC)]
            optimal_labels <- one_batch_matrix_label_df[[optimal_label_name]]
            
            pdf("contingency_heatmap.pdf")
            print(contingency_heatmap(benchmark_label = one_batch_matrix_celltype,
            	candidate_label = optimal_labels,
            	rename_candidate_clusters = TRUE,
            	candidate_cluster_names = paste0('cluster', seq_len(length(unique(optimal_labels))))))
            dev.off()
          }, error = function(e) {
            warning("Skipped contingency_heatmap: optimal label column not found or incompatible in one_batch_matrix_label_df.")
            if (dev.cur() > 1) dev.off()
          })
        
          # Calculate CDI for benchmark labels
          benchmark_return1 <- calculate_CDI(X = sub_one_batch_matrix,
          	cand_lab_df = one_batch_matrix_celltype, 
          	batch_label = NULL, 
          	cell_size_factor = one_batch_matrix_size_factor)
          
          write.csv(benchmark_return1, "benchmark_CDI_results.csv", row.names = FALSE)
        
          # Add benchmark to the lineplot
          pdf("CDI_lineplot_with_benchmark.pdf")
          print(CDI_lineplot(cdi_dataframe = CDI_return1,
          	cdi_type = "CDI_BIC",
          	benchmark_celltype_cdi = benchmark_return1,
          	benchmark_celltype_ncluster = length(unique(one_batch_matrix_celltype))))
          dev.off()
        }

    writeLines(c(
        '"BIOC_CDI_SINGLE_BATCH_CDI":',
        paste0('    CDI: ', as.character(packageVersion('CDI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_batch_cdi.csv versions.yml
    """
}

workflow BIOC_CDI_SINGLE_BATCH_CDI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ one_batch_matrix, one_batch_matrix_label_df, one_batch_matrix_celltype ] ]

    main:
    BIOC_CDI_SINGLE_BATCH_CDI(ch_input)

    emit:
    tables   = BIOC_CDI_SINGLE_BATCH_CDI.out.tables
    plots    = BIOC_CDI_SINGLE_BATCH_CDI.out.plots
    objects  = BIOC_CDI_SINGLE_BATCH_CDI.out.objects
    versions = BIOC_CDI_SINGLE_BATCH_CDI.out.versions
}
