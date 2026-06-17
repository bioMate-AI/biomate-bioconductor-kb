#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clustComp — flat_vs_hierarchical_comparison
// Compare a hierarchical clustering tree with a flat clustering to identify optimal cutoffs and visualize branch-to-cluster relationships.
// Input: hierar, flat1, expression_matrix
// Container: quay.io/biocontainers/bioconductor-clustcomp:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: clustComp
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Compare hierarchical and flat clusterings using an
//  * 2. [Visualization & Output] Generate an expanded visualization showing the full
//  * 3. [Visualization & Output] Compare clusterings using an information theory-based
//  * 4. [Visualization & Output] Generate an expanded visualization of the comparison

nextflow.enable.dsl = 2

process BIOC_CLUSTCOMP_FLAT_VS_HIERARCHICAL_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("clustComp")
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
    library(clustComp)
    
    # Helper function to robustly load user inputs
    load_input <- function(filepath) {
      if (!file.exists(filepath)) {
        # Try with common extensions
        extensions <- c(".rds", ".csv", ".tsv", ".txt")
        found <- FALSE
        for (ext in extensions) {
          if (file.exists(paste0(filepath, ext))) {
            filepath <- paste0(filepath, ext)
            found <- TRUE
            break
          }
        }
        if (!found) {
          stop(paste("Required input file not found:", filepath))
        }
      }
      
      # Try reading as RDS (best for hclust and complex vectors/matrices)
      obj <- tryCatch(readRDS(filepath), error = function(e) NULL)
      if (!is.null(obj)) return(obj)
      
      # Try reading as matrix/df (for expression matrix)
      df <- tryCatch({
        as.matrix(read.table(filepath, header=TRUE, row.names=1, sep="\t"))
      }, error = function(e) NULL)
      if (!is.null(df)) return(df)
      
      df <- tryCatch({
        as.matrix(read.csv(filepath, header=TRUE, row.names=1))
      }, error = function(e) NULL)
      if (!is.null(df)) return(df)
      
      # Try reading as simple vector (for flat1)
      vec <- tryCatch({
        scan(filepath, what=character(), quiet=TRUE)
      }, error = function(e) NULL)
      if (!is.null(vec)) return(vec)
      
      stop(paste("Could not parse file:", filepath))
    }
    
    # 1. Load User Inputs
    hierar <- load_input("hierar")
    flat1 <- load_input("flat1")
    expression_matrix <- as.matrix(load_input("expression_matrix"))
    
    # Construct hierar2 (Ward's linkage) from the expression matrix as described in the workflow
    hierar2 <- tryCatch({
      hclust(dist(expression_matrix), method = 'ward.D')
    }, error = function(e) {
      warning("Could not compute hierar2 using ward.D from expression_matrix. Falling back to hierar.")
      hierar
    })
    
    # 2. Execute Workflow Stages and Save Outputs
    
    # --- Compare hierarchical and flat clusterings using an ---
    pdf("plot_flatVShier_1.pdf", width = 8, height = 6)
    comparison.flatVShier.1<-flatVShier(hierar, flat1, verbose=FALSE, pausing=FALSE, score.function="crossing", greedy.colours=1:4, look.ahead=0)
    dev.off()
    saveRDS(comparison.flatVShier.1, "comparison_flatVShier_1.rds")
    
    # --- Generate an expanded visualization showing the full ---
    pdf("plot_flatVShier_1_expanded.pdf", width = 8, height = 14)
    comparison.flatVShier.1<-flatVShier(hierar, flat1, verbose=FALSE, pausing=FALSE, score.function="crossing", greedy.colours=1:4, look.ahead=0, expanded=TRUE)
    dev.off()
    saveRDS(comparison.flatVShier.1, "comparison_flatVShier_1_expanded.rds")
    
    # --- Compare clusterings using an information theory-based ---
    pdf("plot_flatVShier_2.pdf", width = 8, height = 6)
    comparison.flatVShier.2<-flatVShier(hierar, flat1, verbose=FALSE, pausing=FALSE, h.min=0.2, score.function="it", greedy.colours=1:4, look.ahead=1)
    dev.off()
    saveRDS(comparison.flatVShier.2, "comparison_flatVShier_2.rds")
    
    pdf("plot_flatVShier_3.pdf", width = 8, height = 6)
    comparison.flatVShier.3<-flatVShier(hierar, flat1, verbose=FALSE, pausing=FALSE, h.min=0.2, score.function="it", greedy.colours=1:4, look.ahead=2)
    dev.off()
    saveRDS(comparison.flatVShier.3, "comparison_flatVShier_3.rds")
    
    pdf("plot_flatVShier_4.pdf", width = 8, height = 14)
    comparison.flatVShier.4<-flatVShier(hierar2, flat1, verbose=FALSE, pausing=FALSE, h.min=0.2, score.function="it", greedy.colours=1:4, look.ahead=2, expanded=TRUE)
    dev.off()
    saveRDS(comparison.flatVShier.4, "comparison_flatVShier_4.rds")
    
    # --- Generate an expanded visualization of the comparison ---
    pdf("plot_flatVShier_5.pdf", width = 8, height = 14)
    comparison.flatVShier.5<-flatVShier(hierar2, flat1, verbose=FALSE, pausing=FALSE, h.min=0.2, score.function="it", greedy.colours=1:4, look.ahead=2, expanded=TRUE, expression=expression_matrix)
    dev.off()
    saveRDS(comparison.flatVShier.5, "comparison_flatVShier_5.rds")

    writeLines(c(
        '"BIOC_CLUSTCOMP_FLAT_VS_HIERARCHICAL_COMPARISON":',
        paste0('    clustComp: ', as.character(packageVersion('clustComp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flat_vs_hierarchical_comparison.csv versions.yml
    """
}

workflow BIOC_CLUSTCOMP_FLAT_VS_HIERARCHICAL_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hierar, flat1, expression_matrix ] ]

    main:
    BIOC_CLUSTCOMP_FLAT_VS_HIERARCHICAL_COMPARISON(ch_input)

    emit:
    tables   = BIOC_CLUSTCOMP_FLAT_VS_HIERARCHICAL_COMPARISON.out.tables
    plots    = BIOC_CLUSTCOMP_FLAT_VS_HIERARCHICAL_COMPARISON.out.plots
    objects  = BIOC_CLUSTCOMP_FLAT_VS_HIERARCHICAL_COMPARISON.out.objects
    versions = BIOC_CLUSTCOMP_FLAT_VS_HIERARCHICAL_COMPARISON.out.versions
}
