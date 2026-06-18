#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: optimalFlow — template_generation_and_clustering
// Cluster a database of gated cytometries and generate representative prototype (template) cytometries.
// Input: database
// Container: quay.io/biocontainers/bioconductor-optimalflow:1.22.0--r45h575d39b_0
// R packages: ellipse, optimalFlow, optimalflowdata
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_OPTIMALFLOW_TEMPLATE_GENERATION_AND_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-optimalflow:1.22.0--r45h575d39b_0"

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
    .bm_deps <- c("ellipse", "optimalFlow", "optimalflowdata")
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
    library(optimalFlow)
    library(ellipse)
    
    # --- Read the user input database file from the working ---
    database_file <- "database.rds"
    if (!file.exists(database_file) && file.exists("database")) {
      database_file <- "database"
    }
    
    if (!file.exists(database_file)) {
      stop("Error: User input 'database' file not found in the working directory.")
    }
    
    database_input <- readRDS(database_file)
    
    # Reconstruct individual cytometry datasets in the global environment
    # so that buildDatabase can access them by name.
    dataset_names <- paste0('Cytometry', c(2:5, 7:9, 12:17, 19, 21))
    for (i in seq_along(dataset_names)) {
      assign(dataset_names[i], database_input[[i]], envir = .GlobalEnv)
    }
    
    # --- Build the database of gated cytometries using ---
    database <- buildDatabase(
      dataset_names = paste0('Cytometry', c(2:5, 7:9, 12:17, 19, 21)),
      population_ids = c('Monocytes', 'CD4+CD8-', 'Mature SIg Kappa', 'TCRgd-')
    )
    
    # --- Generate templates and cluster the database using ---
    templates.optimalFlow <-
      optimalFlowTemplates(
        database = database, templates.number = 5, cl.paral = 1
      )
    
    # --- Visualize the database clusters and templates ---
    pdf("optimalFlow_plots.pdf", width = 10, height = 8)
    
    # Plot database elliptical representations for cluster 3
    cytoPlotDatabase(
      templates.optimalFlow\$database.elliptical[which(templates.optimalFlow\$clustering == 3)], 
      dimensions = c(4,3), xlim = c(0, 8000), ylim = c(0, 8000), xlab = "", ylab = ""
    )
    
    # Plot the template corresponding to cluster 3
    cytoPlot(
      templates.optimalFlow\$templates[[3]], 
      dimensions = c(4,3), xlim = c(0, 8000), ylim = c(0, 8000), xlab = "", ylab = ""
    )
    
    dev.off()
    
    # --- Generate templates using alternative consensus and ---
    templates.optimalFlow.barycenter <- 
      optimalFlowTemplates(
        database = database, templates.number = 5, consensus.method = "k-barycenter",
        barycenters.number = 4, bar.repetitions = 10, alpha.bar = 0.05, cl.paral = 1
      )
    
    templates.optimalFlow.hdbscan <- 
      optimalFlowTemplates(
        database = database, templates.number = 5, consensus.method = "hierarchical",
        cl.paral = 1
      )
    
    templates.optimalFlow.unsup <-
      optimalFlowTemplates(
        database = database, hclust.method = "hdbscan", cl.paral = 1, consensus.method = "hierarchical"
      )
    
    # --- Save meaningful results to output files ---
    saveRDS(templates.optimalFlow, "templates_optimalFlow.rds")
    saveRDS(templates.optimalFlow.barycenter, "templates_optimalFlow_barycenter.rds")
    saveRDS(templates.optimalFlow.hdbscan, "templates_optimalFlow_hdbscan.rds")
    saveRDS(templates.optimalFlow.unsup, "templates_optimalFlow_unsup.rds")
    
    # Save clustering results as a CSV table
    clustering_results <- data.frame(
      Dataset = dataset_names,
      OptimalFlow_Clustering = templates.optimalFlow\$clustering,
      Barycenter_Clustering = templates.optimalFlow.barycenter\$clustering,
      HDBSCAN_Clustering = templates.optimalFlow.hdbscan\$clustering,
      Unsupervised_Clustering = templates.optimalFlow.unsup\$clustering
    )
    write.csv(clustering_results, "clustering_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_OPTIMALFLOW_TEMPLATE_GENERATION_AND_CLUSTERING":',
        paste0('        optimalFlow: ', as.character(packageVersion("optimalFlow")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_template_generation_and_clustering.csv versions.yml
    """
}

workflow BIOC_OPTIMALFLOW_TEMPLATE_GENERATION_AND_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ database ] ]

    main:
    BIOC_OPTIMALFLOW_TEMPLATE_GENERATION_AND_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_OPTIMALFLOW_TEMPLATE_GENERATION_AND_CLUSTERING.out.tables
    plots    = BIOC_OPTIMALFLOW_TEMPLATE_GENERATION_AND_CLUSTERING.out.plots
    objects  = BIOC_OPTIMALFLOW_TEMPLATE_GENERATION_AND_CLUSTERING.out.objects
    versions = BIOC_OPTIMALFLOW_TEMPLATE_GENERATION_AND_CLUSTERING.out.versions
}
