#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tmixclust — expression_set_clustering
// Load time series gene expression data from a Biobase ExpressionSet object, convert it to a compatible data frame, and perform clustering.
// Input: sos
// Container: quay.io/biocontainers/bioconductor-tmixclust:1.32.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TMIXCLUST_EXPRESSION_SET_CLUSTERING {
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
    .bm_deps <- c("Biobase", "SPEM", "TMixClust")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(TMixClust)
    library(SPEM)
    library(Biobase)
    
    # 1. Load the Biobase ExpressionSet object from the user input file 'sos'
    if (file.exists("sos")) {
      sos <- readRDS("sos")
    } else if (file.exists("sos.rds")) {
      sos <- readRDS("sos.rds")
    } else {
      stop("Required input file 'sos' (Biobase ExpressionSet) not found in the working directory.")
    }
    
    # 2. Convert the ExpressionSet to a time series data frame
    sos_data = get_time_series_df_bio(sos)
    print(head(sos_data))
    
    # Save the converted data frame to a CSV file
    write.csv(sos_data, file = "sos_data.csv", row.names = TRUE)
    
    # 3. Perform clustering on the retrieved data frame
    cluster_obj = TMixClust(sos_data, nb_clusters = 3)
    
    # Save the clustering object to an RDS file
    saveRDS(cluster_obj, file = "cluster_obj.rds")
    
    # Generate and save a silhouette plot of the clustering result
    tryCatch({
      pdf("silhouette_plot.pdf")
      plot_silhouette(cluster_obj)
      dev.off()
    }, error = function(e) {
      warning("Could not generate silhouette plot: ", e\$message)
    })
    
    # Generate and save a time series plot of the data
    tryCatch({
      pdf("time_series_plot.pdf")
      plot_time_series_df(sos_data, plot_title = "SOS Time Series Data")
      dev.off()
    }, error = function(e) {
      warning("Could not generate time series plot: ", e\$message)
    })
    
    cat("Pipeline completed successfully. Outputs saved: 'sos_data.csv', 'cluster_obj.rds', 'silhouette_plot.pdf', 'time_series_plot.pdf'\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TMIXCLUST_EXPRESSION_SET_CLUSTERING":
        tmixclust: \$(Rscript -e 'cat(as.character(packageVersion("tmixclust")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expression_set_clustering.csv versions.yml
    """
}

workflow BIOC_TMIXCLUST_EXPRESSION_SET_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sos ] ]

    main:
    BIOC_TMIXCLUST_EXPRESSION_SET_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_TMIXCLUST_EXPRESSION_SET_CLUSTERING.out.tables
    plots    = BIOC_TMIXCLUST_EXPRESSION_SET_CLUSTERING.out.plots
    objects  = BIOC_TMIXCLUST_EXPRESSION_SET_CLUSTERING.out.objects
    versions = BIOC_TMIXCLUST_EXPRESSION_SET_CLUSTERING.out.versions
}
