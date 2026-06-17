#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clipper — global_and_subpath_clipper_analysis
// Perform a two-step topological pathway analysis to test global pathway significance and identify specific active sub-paths.
// Input: expression_data.RData, class_labels.RData, pathway_graph.RData
// Container: quay.io/biocontainers/bioconductor-clipper:1.50.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, clipper, graph
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run global pathway analysis using pathQ to test for differences in covariance and mean
//  * 2. [Core Analysis] Identify specific sub-paths associated with the phenotype using clipper
//  * 3. [Core Analysis] Prune overlapping or redundant sub-paths using prunePaths
//  * 4. [Visualization & Output] Visualize the identified sub-paths using plotInCytoscape

nextflow.enable.dsl = 2

process BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("clipper", "graph", "Biobase")
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
    library(clipper)
    library(graph)
    library(Biobase)
    
    # Helper function to load RData and extract the object
    load_rdata_object <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Required input file missing:", file_path))
      }
      temp_env <- new.env()
      loaded_names <- load(file_path, envir = temp_env)
      if (length(loaded_names) == 0) {
        stop(paste("No objects found in", file_path))
      }
      return(temp_env[[loaded_names[1]]])
    }
    
    # 1. Read the declared USER INPUT files
    exp <- load_rdata_object("expression_data.RData")
    classes <- load_rdata_object("class_labels.RData")
    graph <- load_rdata_object("pathway_graph.RData")
    
    # 2. Run global pathway analysis using pathQ to test for differences in covariance and mean
    pathwayAnalysis <- pathQ(exp, classes, graph, nperm=100, alphaV=0.05, b=100)
    pathwayAnalysis
    
    # Save global pathway analysis results
    saveRDS(pathwayAnalysis, file = "pathway_analysis_global.rds")
    
    # 3. Identify specific sub-paths associated with the phenotype using clipper
    clipped <- clipper(exp, classes, graph, "var", trZero=0.01, permute=FALSE)
    clipped[,1:5]
    
    # Save raw clipped paths
    write.csv(as.data.frame(clipped), file = "clipped_paths_raw.csv", row.names = TRUE)
    
    # 4. Prune overlapping or redundant sub-paths using prunePaths
    clipped <- prunePaths(clipped, thr=0.2)
    clipped[,1:5]
    
    # Save pruned clipped paths
    write.csv(as.data.frame(clipped), file = "clipped_paths_pruned.csv", row.names = TRUE)
    
    # 5. Visualize the identified sub-paths using plotInCytoscape
    # Wrapped in tryCatch to handle environments where Cytoscape is not running
    tryCatch({
      if (nrow(clipped) > 0) {
        plotInCytoscape(graph, clipped[1,])
      } else {
        warning("No paths available to plot in Cytoscape.")
      }
    }, error = function(e) {
      message("Could not plot in Cytoscape. Ensure Cytoscape is running and RCy3 is configured properly.")
      message("Error details: ", e\$message)
    })

    writeLines(c(
        '"BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS":',
        paste0('    clipper: ', as.character(packageVersion('clipper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_global_and_subpath_clipper_analysis.csv versions.yml
    """
}

workflow BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.RData, class_labels.RData, pathway_graph.RData ] ]

    main:
    BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS.out.tables
    plots    = BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS.out.plots
    objects  = BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS.out.objects
    versions = BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS.out.versions
}
