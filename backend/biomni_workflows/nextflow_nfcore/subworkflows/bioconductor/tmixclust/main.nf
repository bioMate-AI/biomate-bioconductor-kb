#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tmixclust — text_file_clustering
// Load time series gene expression data from a text file, perform clustering, run stability analysis to find the global optimum, validate the results with silhoue
// Input: toy_time_series.txt
// Container: quay.io/biocontainers/bioconductor-tmixclust:1.32.0--r45hdfd78af_0
// R packages: SPEM, TMixClust
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_TMIXCLUST_TEXT_FILE_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-tmixclust:1.32.0--r45hdfd78af_0"

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
    .bm_deps <- c("SPEM", "TMixClust")
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
    
    # Load the required library
    library(TMixClust)
    
    # Define the input file path (must be in the working directory)
    toy_data_file <- "toy_time_series.txt"
    
    # Verify that the input file exists
    if (!file.exists(toy_data_file)) {
      stop(paste("Error: Input file", toy_data_file, "not found in the working directory."))
    }
    
    # --- Load the time series data from the text file ---
    toy_data <- get_time_series_df(toy_data_file)
    
    # Open a PDF device to save all generated plots
    pdf_output_file <- "TMixClust_plots.pdf"
    pdf(pdf_output_file, width = 8, height = 6)
    
    # --- Visualize the raw time series data ---
    plot_time_series_df(toy_data)
    
    # --- Perform initial clustering (K = 3) ---
    cluster_obj <- TMixClust(toy_data, nb_clusters = 3)
    
    # --- Run stability analysis to find the global optimum ---
    # (Runs the clustering 10 times using 3 cores)
    best_clust_toy_obj <- analyse_stability(toy_data, nb_clusters = 3,
                                           nb_clustering_runs = 10,
                                           nb_cores = 3)
    
    # --- Plot the time series for each identified cluster ---
    for (i in 1:3) {
        c_df = toy_data[which(best_clust_toy_obj\$em_cluster_assignment == i), ]
        plot_time_series_df(c_df, plot_title = paste("cluster", i))
    }
    
    # --- Generate a silhouette plot to validate cluster quality ---
    plot_silhouette(best_clust_toy_obj)
    
    # Close the PDF device
    dev.off()
    
    # --- Generate a comprehensive HTML/PDF report ---
    # This will create a folder named "TMixClust_report/" in the working directory
    generate_TMixClust_report(cluster_obj)
    
    # Save the clustering results and objects to disk
    saveRDS(cluster_obj, "initial_cluster_obj.rds")
    saveRDS(best_clust_toy_obj, "best_cluster_stability_obj.rds")
    
    # Export cluster assignments to a CSV file
    assignments_df <- data.frame(
      Gene = rownames(toy_data),
      Cluster_Assignment = best_clust_toy_obj\$em_cluster_assignment
    )
    write.csv(assignments_df, "gene_cluster_assignments.csv", row.names = FALSE)
    
    cat("Pipeline completed successfully.\n")
    cat("Outputs generated:\n")
    cat("- TMixClust_plots.pdf (Visualization of raw data, clusters, and silhouette plot)\n")
    cat("- TMixClust_report/ (Comprehensive HTML report directory)\n")
    cat("- initial_cluster_obj.rds (Serialized initial clustering object)\n")
    cat("- best_cluster_stability_obj.rds (Serialized optimal clustering object)\n")
    cat("- gene_cluster_assignments.csv (Table of gene cluster assignments)\n")

    writeLines(c(
        '"BIOC_TMIXCLUST_TEXT_FILE_CLUSTERING":',
        paste0('        tmixclust: ', as.character(packageVersion("tmixclust")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_text_file_clustering.csv versions.yml
    """
}

workflow BIOC_TMIXCLUST_TEXT_FILE_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ toy_time_series.txt ] ]

    main:
    BIOC_TMIXCLUST_TEXT_FILE_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_TMIXCLUST_TEXT_FILE_CLUSTERING.out.tables
    plots    = BIOC_TMIXCLUST_TEXT_FILE_CLUSTERING.out.plots
    objects  = BIOC_TMIXCLUST_TEXT_FILE_CLUSTERING.out.objects
    versions = BIOC_TMIXCLUST_TEXT_FILE_CLUSTERING.out.versions
}
