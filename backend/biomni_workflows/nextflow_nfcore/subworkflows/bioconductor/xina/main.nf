#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: XINA — xina_time_series_clustering_and_network_analysis
// Cluster multiplexed time-series omics data across multiple conditions, identify comigrated features, and perform PPI network analysis.
// Input: Control.csv, Stimulus1.csv, Stimulus2.csv
// Container: quay.io/biocontainers/bioconductor-xina:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: STRINGdb, XINA, ggplot2
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load quantitative time-series datasets for each condition
//  * 2. [Input & Preparation] Define the time points (columns) and data files
//  * 3. [Core Analysis] Perform model-based or k-means clustering using xina_clustering
//  * 4. [Visualization & Output] Plot the clusters using plot_clusters and condition compositions using plot_condition_compositions
//  * 5. [Core Analysis] Perform coregulation/comigration analysis using alluvial_enriched
//  * 6. [Core Analysis] Perform PPI network analysis using STRINGdb and xina_analysis
//  * 7. [Visualization & Output] Plot PPI networks using xina_plot_all

nextflow.enable.dsl = 2

process BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS {
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
    .bm_deps <- c("XINA", "ggplot2", "STRINGdb")
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
    library(XINA)
    library(ggplot2)
    
    # 1. Load quantitative time-series datasets for each condition from the working directory
    Control <- read.csv("Control.csv", check.names=FALSE, stringsAsFactors = FALSE)
    Stimulus1 <- read.csv("Stimulus1.csv", check.names=FALSE, stringsAsFactors = FALSE)
    Stimulus2 <- read.csv("Stimulus2.csv", check.names=FALSE, stringsAsFactors = FALSE)
    
    # 2. Define the time points (columns) and data files
    # We identify the time-series columns by excluding non-numeric metadata columns
    data_column <- setdiff(colnames(Control), c("Accession", "Description"))
    data_files <- c("Control.csv", "Stimulus1.csv", "Stimulus2.csv")
    
    # Set seed for reproducibility
    set.seed(0)
    
    # 3. Perform model-based or k-means clustering using xina_clustering
    clustering_result <- xina_clustering(data_files, data_column=data_column, nClusters=20)
    clustering_result_km <- xina_clustering(data_files, data_column=data_column, nClusters=20, chosen_model='kmeans')
    
    # Save clustering results
    saveRDS(clustering_result, "clustering_result_mclust.rds")
    saveRDS(clustering_result_km, "clustering_result_kmeans.rds")
    
    # 4. Plot the clusters and condition compositions
    theme1 <- theme(title=element_text(size=8, face='bold'),
                    axis.text.x = element_text(size=7),
                    axis.text.y = element_blank(),
                    axis.ticks.x = element_blank(),
                    axis.ticks.y = element_blank(),
                    axis.title.x = element_blank(),
                    axis.title.y = element_blank())
    
    pdf("clusters_plot.pdf", width=10, height=8)
    plot_clusters(clustering_result, ggplot_theme=theme1)
    dev.off()
    
    theme2 <- theme(legend.key.size = unit(0.3, "cm"),
                    legend.text=element_text(size=5),
                    title=element_text(size=7, face='bold'))
    
    pdf("condition_compositions_plot.pdf", width=10, height=8)
    condition_composition <- plot_condition_compositions(clustering_result, ggplot_theme=theme2)
    dev.off()
    
    write.csv(condition_composition, "condition_composition.csv", row.names=FALSE)
    
    # 5. Perform coregulation/comigration analysis using alluvial_enriched
    classes <- as.vector(clustering_result\$condition)
    
    pdf("alluvial_plot_all.pdf", width=10, height=8)
    all_cor <- alluvial_enriched(clustering_result, classes)
    dev.off()
    
    pdf("alluvial_plot_size5.pdf", width=10, height=8)
    cor_bigger_than_5 <- alluvial_enriched(clustering_result, classes, comigration_size=5)
    dev.off()
    
    write.csv(all_cor, "alluvial_all_cor.csv", row.names=FALSE)
    write.csv(cor_bigger_than_5, "alluvial_cor_bigger_than_5.csv", row.names=FALSE)
    
    # 6. Perform PPI network analysis using STRINGdb and xina_analysis
    # Wrapped in tryCatch to handle potential network/download issues gracefully
    tryCatch({
      library(STRINGdb)
      string_db <- STRINGdb\$new( version="10", species=9606, score_threshold=0, input_directory="" )
      xina_result <- xina_analysis(clustering_result, string_db)
      saveRDS(xina_result, "xina_network_analysis_result.rds")
      
      # 7. Plot PPI networks using xina_plot_all
      # This function automatically writes network plots to the working directory
      xina_plot_all(xina_result, clustering_result)
    }, error = function(e) {
      warning("STRINGdb PPI network analysis could not be completed: ", e\$message)
    })

    writeLines(c(
        '"BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS":',
        paste0('    XINA: ', as.character(packageVersion('XINA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xina_time_series_clustering_and_network_analysis.csv versions.yml
    """
}

workflow BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Control.csv, Stimulus1.csv, Stimulus2.csv ] ]

    main:
    BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS.out.tables
    plots    = BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS.out.plots
    objects  = BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS.out.objects
    versions = BIOC_XINA_XINA_TIME_SERIES_CLUSTERING_AND_NETWORK_ANALYSIS.out.versions
}
