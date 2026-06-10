#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PhyloProfile — profile_clustering
// Cluster genes based on the distance of their phylogenetic profiles and plot a dendrogram.
// Input: processed_profile.RData
// Container: quay.io/biocontainers/bioconductor-phyloprofile:2.2.2--r45hdfd78af_0
// R packages: PhyloProfile
// Bioconductor: 3.20 | R: 4.4
// Requires: PhyloProfile
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Aggregate profile data using `getDataClustering`
//  * 2. [Core Analysis] Calculate distance matrix using `getDistanceMatrix`
//  * 3. [Core Analysis] Perform hierarchical clustering using `clusterDataDend`
//  * 4. [Visualization & Output] Plot the dendrogram using `getDendrogram`

nextflow.enable.dsl = 2

process BIOC_PHYLOPROFILE_PROFILE_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("PhyloProfile")
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
    library(PhyloProfile)
    
    # Check for the existence of the required input file
    input_file <- "processed_profile.RData"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Load the processed profile data
    env <- new.env()
    load(input_file, envir = env)
    
    # Identify the main data frame object from the loaded RData
    obj_names <- names(env)
    data_obj_name <- NULL
    for (name in obj_names) {
      if (is.data.frame(env[[name]])) {
        data_obj_name <- name
        break
      }
    }
    
    if (is.null(data_obj_name)) {
      if (length(obj_names) > 0) {
        data_obj_name <- obj_names[1]
      } else {
        stop("The loaded RData file is empty.")
      }
    }
    
    data <- env[[data_obj_name]]
    
    # Set aggregation parameters (use loaded values if present, otherwise defaults)
    if ("var1AggregateBy" %in% names(env)) {
      var1AggregateBy <- env[["var1AggregateBy"]]
    } else {
      var1AggregateBy <- "max"
    }
    
    if ("var2AggregateBy" %in% names(env)) {
      var2AggregateBy <- env[["var2AggregateBy"]]
    } else {
      var2AggregateBy <- "mean"
    }
    
    # ==========================================
    # DOCUMENTED CODE FOR WORKFLOW
    # ==========================================
    
    profileType <- "binary"
    profiles <- getDataClustering(
        data, profileType, var1AggregateBy, var2AggregateBy)
    method <- "mutualInformation"
    distanceMatrix <- getDistanceMatrix(profiles, method)
    clusterMethod <- "complete"
    dd <- clusterDataDend(as.dist(distanceMatrix), clusterMethod)
    
    # Save the dendrogram plot to a PDF file
    pdf("dendrogram.pdf", width = 10, height = 8)
    p <- getDendrogram(dd)
    if (!is.null(p)) {
      tryCatch(print(p), error = function(e) NULL)
    }
    dev.off()
    
    # ==========================================
    # SAVE OUTPUTS
    # ==========================================
    
    # Save the distance matrix as a CSV file
    write.csv(as.matrix(distanceMatrix), "distance_matrix.csv", row.names = TRUE)
    
    # Save the clustered profiles data frame as a CSV file
    write.csv(profiles, "profiles_clustering.csv", row.names = TRUE)
    
    # Save the dendrogram object as an RDS file
    saveRDS(dd, "dendrogram.rds")

    writeLines(c(
        '"BIOC_PHYLOPROFILE_PROFILE_CLUSTERING":',
        paste0('    PhyloProfile: ', as.character(packageVersion('PhyloProfile')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_profile_clustering.csv versions.yml
    """
}

workflow BIOC_PHYLOPROFILE_PROFILE_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ processed_profile.RData ] ]

    main:
    BIOC_PHYLOPROFILE_PROFILE_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_PHYLOPROFILE_PROFILE_CLUSTERING.out.tables
    plots    = BIOC_PHYLOPROFILE_PROFILE_CLUSTERING.out.plots
    objects  = BIOC_PHYLOPROFILE_PROFILE_CLUSTERING.out.objects
    versions = BIOC_PHYLOPROFILE_PROFILE_CLUSTERING.out.versions
}
