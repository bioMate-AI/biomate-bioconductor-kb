#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: diffcyt — diffcyt_wrapper_pipeline
// Run the complete differential abundance (DA) or differential state (DS) analysis using the single wrapper function diffcyt().
// Input: d_flowSet, experiment_info, marker_info
// Container: quay.io/biocontainers/bioconductor-diffcyt:1.30.0--r45hdfd78af_0
// R packages: diffcyt, flowCore, hdcytodata
// Bioconductor: 3.20 | R: 4.4
// Requires: diffcyt, flowCore
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] READ USER INPUTS FROM WORKING DIRECTORY
//  * 2. [Input & Preparation] RUN THE DOCUMENTED DIFFCYT PIPELINE
//  * 3. [Input & Preparation] WRITE OUTPUT FILES

nextflow.enable.dsl = 2

process BIOC_DIFFCYT_DIFFCYT_WRAPPER_PIPELINE {
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
    .bm_deps <- c("diffcyt", "flowCore", "hdcytodata")
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
        library(diffcyt)
        library(flowCore)
        
        # ==========================================
        # --- READ USER INPUTS FROM WORKING DIRECTORY ---
        # ==========================================
        
        # Read d_flowSet (flowSet object)
        if (file.exists("d_flowSet.rds")) {
          d_flowSet <- readRDS("d_flowSet.rds")
        } else {
          stop("Error: Required input file 'd_flowSet.rds' not found in the working directory.")
        }
        
        # Read experiment_info (data frame)
        if (file.exists("experiment_info.rds")) {
          experiment_info <- readRDS("experiment_info.rds")
        } else if (file.exists("experiment_info.csv")) {
          experiment_info <- read.csv("experiment_info.csv", stringsAsFactors = FALSE)
          # Ensure factors are correctly set up as expected by the workflow
          if ("group_id" %in% colnames(experiment_info)) {
            experiment_info\$group_id <- factor(experiment_info\$group_id)
          }
          if ("patient_id" %in% colnames(experiment_info)) {
            experiment_info\$patient_id <- factor(experiment_info\$patient_id)
          }
        } else {
          stop("Error: Required input file 'experiment_info' (.rds or .csv) not found in the working directory.")
        }
        
        # Read marker_info (data frame)
        if (file.exists("marker_info.rds")) {
          marker_info <- readRDS("marker_info.rds")
        } else if (file.exists("marker_info.csv")) {
          marker_info <- read.csv("marker_info.csv", stringsAsFactors = FALSE)
          # Ensure marker_class is a factor with correct levels
          if ("marker_class" %in% colnames(marker_info)) {
            marker_info\$marker_class <- factor(marker_info\$marker_class, levels = c("type", "state", "none"))
          }
        } else {
          stop("Error: Required input file 'marker_info' (.rds or .csv) not found in the working directory.")
        }
        
        
        # ==========================================
        # --- RUN THE DOCUMENTED DIFFCYT PIPELINE ---
        # ==========================================
        
        # Create design matrix
        cols_design <- "group_id"
        if ("patient_id" %in% colnames(experiment_info)) {
          cols_design <- c("group_id", "patient_id")
        }
        
        design <- createDesignMatrix(
          experiment_info, cols_design = cols_design
        )
        
        # Create contrast matrix
        contrast_vec <- rep(0, ncol(design))
        contrast_vec[2] <- 1
        contrast <- createContrast(contrast_vec)
        
        # Test for differential abundance (DA) of clusters
        out_DA <- diffcyt(
          d_input = d_flowSet, 
          experiment_info = experiment_info, 
          marker_info = marker_info, 
          design = design, 
          contrast = contrast, 
          analysis_type = "DA", 
          seed_clustering = 123
        )
        
        # Display table of results for top DA clusters
        da_table <- topTable(out_DA, format_vals = TRUE)
        print("Top DA Clusters:")
        print(da_table)
        
        # Test for differential states (DS) within clusters
        out_DS <- diffcyt(
          d_input = d_flowSet, 
          experiment_info = experiment_info, 
          marker_info = marker_info, 
          design = design, 
          contrast = contrast, 
          analysis_type = "DS", 
          seed_clustering = 123, 
          plot = FALSE
        )
        
        # Display table of results for top DS cluster-marker combinations
        ds_table <- topTable(out_DS, format_vals = TRUE)
        print("Top DS Cluster-Marker Combinations:")
        print(ds_table)
        
        
        # ==========================================
        # --- WRITE OUTPUT FILES ---
        # ==========================================
        
        # Save RDS objects of the full results
        saveRDS(out_DA, "out_DA.rds")
        saveRDS(out_DS, "out_DS.rds")
        
        # Save CSV tables of the top results
        write.csv(as.data.frame(da_table), "top_DA_clusters.csv", row.names = FALSE)
        write.csv(as.data.frame(ds_table), "top_DS_combinations.csv", row.names = FALSE)
        
        # Generate and save diagnostic heatmaps
        tryCatch({
          pdf("heatmap_DA.pdf", width = 10, height = 8)
          sample_order <- order(experiment_info\$group_id)
          plotHeatmap(out_DA, analysis_type = "DA", sample_order = sample_order)
          dev.off()
        }, error = function(e) {
          message("Warning: Could not generate DA heatmap. ", e\$message)
        })
        
        tryCatch({
          pdf("heatmap_DS.pdf", width = 10, height = 8)
          sample_order <- order(experiment_info\$group_id)
          plotHeatmap(out_DS, analysis_type = "DS", sample_order = sample_order)
          dev.off()
        }, error = function(e) {
          message("Warning: Could not generate DS heatmap. ", e\$message)
        })

    writeLines(c(
        '"BIOC_DIFFCYT_DIFFCYT_WRAPPER_PIPELINE":',
        paste0('    diffcyt: ', as.character(packageVersion('diffcyt')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diffcyt_wrapper_pipeline.csv versions.yml
    """
}

workflow BIOC_DIFFCYT_DIFFCYT_WRAPPER_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ d_flowSet, experiment_info, marker_info ] ]

    main:
    BIOC_DIFFCYT_DIFFCYT_WRAPPER_PIPELINE(ch_input)

    emit:
    tables   = BIOC_DIFFCYT_DIFFCYT_WRAPPER_PIPELINE.out.tables
    plots    = BIOC_DIFFCYT_DIFFCYT_WRAPPER_PIPELINE.out.plots
    objects  = BIOC_DIFFCYT_DIFFCYT_WRAPPER_PIPELINE.out.objects
    versions = BIOC_DIFFCYT_DIFFCYT_WRAPPER_PIPELINE.out.versions
}
