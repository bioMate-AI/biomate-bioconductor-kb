#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: omicspca — multi_assay_integration_and_clustering
// Integrate multiple distinct omics assays, analyze the integrated multi-omics space, determine optimal clustering parameters, and cluster genomic features.
// Input: multi_assay, groupinfo
// Container: quay.io/biocontainers/bioconductor-omicspca:1.28.0--r45h575d39b_0
// R packages: MultiAssayExperiment, OMICsPCA, cluster, factoextra
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: factoextra plot, elbow plot, density plot, cluster plot, box plot

nextflow.enable.dsl = 2

process BIOC_OMICSPCA_MULTI_ASSAY_INTEGRATION_AND_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-omicspca:1.28.0--r45h575d39b_0"

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
    .bm_deps <- c("MultiAssayExperiment", "OMICsPCA", "cluster", "factoextra")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(OMICsPCA)
    library(MultiAssayExperiment)
    library(factoextra)
    library(cluster)
    
    # Read user input files from the working directory
    if (file.exists("multi_assay")) {
      multi_assay <- readRDS("multi_assay")
    } else if (file.exists("multi_assay.rds")) {
      multi_assay <- readRDS("multi_assay.rds")
    } else {
      stop("Required input file 'multi_assay' or 'multi_assay.rds' not found in the working directory.")
    }
    
    if (file.exists("groupinfo")) {
      groupinfo <- readRDS("groupinfo")
    } else if (file.exists("groupinfo.rds")) {
      groupinfo <- readRDS("groupinfo.rds")
    } else {
      stop("Required input file 'groupinfo' or 'groupinfo.rds' not found in the working directory.")
    }
    
    # --- Integrate multiple assays using integrate_pca() ---
    exclude <- list(0, c(1, 9))
    int_PCA <- integrate_pca(Assays = c("H2az", "H3k9ac"), groupinfo = groupinfo, name = multi_assay, mergetype = 2, exclude = exclude, graph = FALSE)
    start_end = int_PCA\$start_end
    name = int_PCA\$int_PCA
    
    # Save integrated PCA object
    saveRDS(int_PCA, "integrated_pca_results.rds")
    
    # --- Analyze integrated variables and individuals using ---
    pdf("integrated_variables_analysis.pdf")
    analyse_integrated_variables(start_end = start_end, name = name, choice = 1, title = "variance barplot", Assay = 1, addlabels = TRUE)
    analyse_integrated_variables(start_end = start_end, Assay = 1, name = name, choice = 2 , title = "Loadings of cell lines on PC1 and PC2", var_type = "contrib")
    analyse_integrated_variables(start_end = start_end, Assay = 1, name = name, choice = 3, title = "Correlation of Cell lines with PCs of integrated Assays", is.cor = TRUE)
    analyse_integrated_variables(start_end = start_end, Assay = 1, name = name, choice = 4, PC = 1, title = "Squarred loadings of Cell lines on PC1 of integrated Assays")
    analyse_integrated_variables(start_end = start_end, Assay = 1, name = name, choice = 5, PC=1, title = "Contribution of Cell lines on PC1 of integrated Assays")
    dev.off()
    
    pdf("integrated_individuals_analysis.pdf")
    analyse_integrated_individuals(name = name, choice = 1, PC = c(1,2), groupinfo = groupinfo)
    analyse_integrated_individuals(name = name, choice = 2, PC = c(1,2,3), col = c("RED", "BLACK","GREEN"), groupinfo = groupinfo)
    dev.off()
    
    # --- Perform density analysis on integrated data using ---
    pdf("density_analysis_plots.pdf")
    densityplot <- plot_integrated_density(name = name, PC = 1, groups = c("WE","RE","IntE","NE"), groupinfo = groupinfo)
    print(densityplot)
    plot_integrated_density_3D(name = name, PC1 = 1, PC2 = 2, group = c("RE","RE"), gridsize = 100, static = TRUE, groupinfo = groupinfo)
    # Wrap non-static 3D plot in try to prevent headless environment crashes
    try(plot_integrated_density_3D(name = name, PC1 = 1, PC2 = 2, group = c("WE","RE"), gridsize = 100, static = FALSE, groupinfo = groupinfo))
    dev.off()
    
    # --- Extract PCA data for clustering using extract() ---
    data <- extract(name = name, PC = c(1:4), groups = c("WE","RE"), integrated = TRUE, rand = 600, groupinfo = groupinfo)
    
    # --- Determine optimal cluster parameters using ---
    clusterstats <- cluster_parameters(name = data, optimal = FALSE, n = 2:6, comparisonAlgorithm = "clValid", distance = "euclidean", clusteringMethods = c("kmeans","pam"), validationMethods = c("internal","stability"))
    clusterstats <- cluster_parameters(name = data, n = 2:6, comparisonAlgorithm = "NbClust", distance = "euclidean", clusteringMethods = "kmeans", validationMethods = "all")
    
    # Save cluster parameters statistics
    saveRDS(clusterstats, "cluster_parameters_results.rds")
    
    pdf("nbclust_optimal_clusters.pdf")
    fviz_nbclust(clusterstats, method = c("silhouette", "wss", "gap_stat"))
    dev.off()
    
    # --- Cluster genomic features using cluster() ---
    data <- extract(name = name, PC = c(1:4), groups = c("WE","RE"), integrated = TRUE, rand = 1000, groupinfo = groupinfo)
    
    pdf("clustering_results.pdf")
    clusters <- cluster(name = data, n = 2, choice = "kmeans", title = "kmeans on 2 clusters")
    print(clusters\$plot)
    clustered_data <- cbind(data,clusters\$cluster\$cluster)
    
    clusters <- cluster(name = data, choice = "density", eps = 2, MinPts = 100, graph = TRUE, title = "eps = 1 and MinPts = 1.5")
    print(clusters\$plot)
    dev.off()
    
    clustered_data <- as.data.frame(cbind(data,clusters\$cluster\$cluster))
    clustered_data <- clustered_data[clustered_data\$V5 != 0, ]
    
    # Save clustered data
    write.csv(clustered_data, "clustered_data.csv", row.names = TRUE)
    
    # --- Validate clusters and identify misclassified points using ---
    dist <- daisy(data)
    sil = silhouette(clusters\$cluster\$cluster,dist)
    misclassified <- which(sil[,3] < 0)
    
    # Save silhouette and misclassified points information
    write.csv(as.data.frame(sil), "silhouette_analysis.csv", row.names = TRUE)
    if (length(misclassified) > 0) {
      write.csv(as.data.frame(sil[misclassified, , drop=FALSE]), "misclassified_points_silhouette.csv", row.names = TRUE)
      # Print head of misclassified points
      print(head(sil[misclassified,]))
      
      # Safely extract subset of misclassified data if indices exist
      subset_indices <- misclassified[intersect(3:7, seq_along(misclassified))]
      if (length(subset_indices) > 0) {
        misclassified_data_subset <- data[subset_indices, , drop=FALSE]
        write.csv(misclassified_data_subset, "misclassified_data_subset.csv", row.names = TRUE)
        print(misclassified_data_subset)
      }
    }
    
    # --- Explore cluster characteristics using cluster_boxplot() ---
    pdf("cluster_boxplot.pdf")
    bp <- cluster_boxplot(name = multi_assay, Assay = "H2az", clusterobject = clustered_data, clustercolumn = 5)
    print(bp)
    dev.off()

    writeLines(c(
        '"BIOC_OMICSPCA_MULTI_ASSAY_INTEGRATION_AND_CLUSTERING":',
        paste0('        omicspca: ', as.character(packageVersion("omicspca")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_assay_integration_and_clustering.csv versions.yml
    """
}

workflow BIOC_OMICSPCA_MULTI_ASSAY_INTEGRATION_AND_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ multi_assay, groupinfo ] ]

    main:
    BIOC_OMICSPCA_MULTI_ASSAY_INTEGRATION_AND_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_OMICSPCA_MULTI_ASSAY_INTEGRATION_AND_CLUSTERING.out.tables
    plots    = BIOC_OMICSPCA_MULTI_ASSAY_INTEGRATION_AND_CLUSTERING.out.plots
    objects  = BIOC_OMICSPCA_MULTI_ASSAY_INTEGRATION_AND_CLUSTERING.out.objects
    versions = BIOC_OMICSPCA_MULTI_ASSAY_INTEGRATION_AND_CLUSTERING.out.versions
}
