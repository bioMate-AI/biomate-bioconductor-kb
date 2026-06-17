#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spatialDE — standard_matrix_workflow
// Identify, classify, and cluster spatially variable genes from raw count matrices and spatial coordinates.
// Input: Rep11_MOB_0, MOB_sample_info
// Container: quay.io/biocontainers/bioconductor-spatialde:1.16.0--r45hdfd78af_0
// R packages: ggplot2, spatialDE, SpatialExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, spatialDE
// Visualizations: plot (ggplot/base)
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out unobserved genes and calculate total counts per spot
//  * 2. [Core Analysis] Stabilize variance using Anscombe's approximation with stabilize()
//  * 3. [Core Analysis] Regress out library size effects using regress_out()
//  * 4. [Core Analysis] Run the SpatialDE test using spatialDE::run()
//  * 5. [Core Analysis] Classify SVGs into interpretable classes using model_search()
//  * 6. [Core Analysis] Group SVGs into spatial patterns using spatial_patterns()
//  * 7. [Visualization & Output] Visualize results using multiGenePlots() and FSV_sig()

nextflow.enable.dsl = 2

process BIOC_SPATIALDE_STANDARD_MATRIX_WORKFLOW {
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
    .bm_deps <- c("ggplot2", "spatialDE", "SpatialExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
            
        # Load required libraries
        library(spatialDE)
        library(ggplot2)
        
        # Helper function to read input files robustly
        read_input_file <- function(filename) {
          if (file.exists(filename)) {
            return(read.csv(filename, row.names = 1, check.names = FALSE))
          } else if (file.exists(paste0(filename, ".csv"))) {
            return(read.csv(paste0(filename, ".csv"), row.names = 1, check.names = FALSE))
          } else if (file.exists(paste0(filename, ".tsv"))) {
            return(read.delim(paste0(filename, ".tsv"), row.names = 1, check.names = FALSE))
          } else {
            stop(paste("Required input file not found:", filename))
          }
        }
        
        # Read user input files
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        Rep11_MOB_0 <- read_input_file("Rep11_MOB_0")
        MOB_sample_info <- read_input_file("MOB_sample_info")
        
        # 1. Filter out unobserved genes and calculate total counts per spot
        Rep11_MOB_0 <- Rep11_MOB_0[rowSums(Rep11_MOB_0) >= 3, ]
        Rep11_MOB_0 <- Rep11_MOB_0[, row.names(MOB_sample_info)]
        MOB_sample_info\$total_counts <- colSums(Rep11_MOB_0)
        X <- MOB_sample_info[, c("x", "y")]
        
        # 2. Stabilize variance using Anscombe's approximation
        norm_expr <- stabilize(Rep11_MOB_0)
        
        # 3. Regress out library size effects
        resid_expr <- regress_out(norm_expr, sample_info = MOB_sample_info)
        
        # 4. Run the SpatialDE test
        results <- spatialDE::run(resid_expr, coordinates = X)
        de_results <- results[results\$qval < 0.05, ]
        
        # 5. Classify SVGs into interpretable classes
        ms_results <- model_search(
            resid_expr,
            coordinates = X,
            de_results = de_results
        )
        
        # 6. Group SVGs into spatial patterns
        sp <- spatial_patterns(
            resid_expr,
            coordinates = X,
            de_results = de_results,
            n_patterns = 4L, length = 1.5
        )
        
        ordered_de_results <- de_results[order(de_results\$qval), ]
        
        # 7. Visualize results and save to PDF
        pdf("spatialDE_plots.pdf", width = 10, height = 10)
        
        print(multiGenePlots(norm_expr,
            coordinates = X,
            head(ordered_de_results\$g, 6),
            point_size = 4,
            viridis_option = "D",
            dark_theme = FALSE
        ))
        
        print(FSV_sig(results, ms_results))
        
        dev.off()
        
        # Save outputs to files
        write.csv(results, "spatialDE_results.csv", row.names = TRUE)
        write.csv(de_results, "spatialDE_de_results.csv", row.names = TRUE)
        write.csv(ms_results, "spatialDE_model_search_results.csv", row.names = TRUE)
        write.csv(sp\$pattern_results, "spatialDE_pattern_results.csv", row.names = TRUE)
        saveRDS(sp, "spatialDE_spatial_patterns.rds")

    writeLines(c(
        '"BIOC_SPATIALDE_STANDARD_MATRIX_WORKFLOW":',
        paste0('    spatialDE: ', as.character(packageVersion('spatialDE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_matrix_workflow.csv versions.yml
    """
}

workflow BIOC_SPATIALDE_STANDARD_MATRIX_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Rep11_MOB_0, MOB_sample_info ] ]

    main:
    BIOC_SPATIALDE_STANDARD_MATRIX_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_SPATIALDE_STANDARD_MATRIX_WORKFLOW.out.tables
    plots    = BIOC_SPATIALDE_STANDARD_MATRIX_WORKFLOW.out.plots
    objects  = BIOC_SPATIALDE_STANDARD_MATRIX_WORKFLOW.out.objects
    versions = BIOC_SPATIALDE_STANDARD_MATRIX_WORKFLOW.out.versions
}
