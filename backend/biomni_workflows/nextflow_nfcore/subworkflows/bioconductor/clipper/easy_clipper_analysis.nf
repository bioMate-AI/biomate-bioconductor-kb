#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clipper — easy_clipper_analysis
// Quickly run a simplified topological pathway analysis to identify altered sub-paths and summarize results.
// Input: expression_data.RData, class_labels.RData, pathway_graph.RData
// Container: quay.io/biocontainers/bioconductor-clipper:1.50.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, clipper, graph
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run simplified analysis using easyClip with a specified method
//  * 2. [Visualization & Output] Summarize and inspect the results using easyLook

nextflow.enable.dsl = 2

process BIOC_CLIPPER_EASY_CLIPPER_ANALYSIS {
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
    library(Biobase)
    library(graph)
    
    # Helper function to load RData and extract the object safely
    load_object <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Required input file missing:", file_path))
      }
      env <- new.env()
      load(file_path, envir = env)
      vars <- ls(env)
      if (length(vars) == 0) {
        stop(paste("No objects found in", file_path))
      }
      return(get(vars[1], envir = env))
    }
    
    # Load user inputs
    exp <- load_object("expression_data.RData")
    classes <- load_object("class_labels.RData")
    graph <- load_object("pathway_graph.RData")
    
    # Execute documented workflow
    clipped <- easyClip(exp, classes, graph, method="mean")
    clipped[,1:5]
    easyLook(clipped)
    
    # Write outputs
    # 1. Save the full clipped matrix as CSV
    write.csv(as.data.frame(clipped), "clipped_results.csv", row.names = TRUE)
    
    # 2. Save the clipped object as RDS
    saveRDS(clipped, "clipped_results.rds")
    
    # 3. Save the easyLook summary to a text file
    sink("easy_look_summary.txt")
    easyLook(clipped)
    sink()
    
    cat("Workflow completed successfully. Outputs saved to 'clipped_results.csv', 'clipped_results.rds', and 'easy_look_summary.txt'.\n")

    writeLines(c(
        '"BIOC_CLIPPER_EASY_CLIPPER_ANALYSIS":',
        paste0('    clipper: ', as.character(packageVersion('clipper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_easy_clipper_analysis.csv versions.yml
    """
}

workflow BIOC_CLIPPER_EASY_CLIPPER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.RData, class_labels.RData, pathway_graph.RData ] ]

    main:
    BIOC_CLIPPER_EASY_CLIPPER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CLIPPER_EASY_CLIPPER_ANALYSIS.out.tables
    plots    = BIOC_CLIPPER_EASY_CLIPPER_ANALYSIS.out.plots
    objects  = BIOC_CLIPPER_EASY_CLIPPER_ANALYSIS.out.objects
    versions = BIOC_CLIPPER_EASY_CLIPPER_ANALYSIS.out.versions
}
