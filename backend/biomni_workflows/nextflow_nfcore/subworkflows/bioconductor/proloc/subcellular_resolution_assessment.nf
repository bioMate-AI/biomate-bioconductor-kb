#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pRoloc — subcellular_resolution_assessment
// Quantify the resolution of a spatial proteomics experiment and assess the tightness of marker clusters using QSep and ClustDist metrics.
// Input: spatial_proteomics_data.rds
// Container: quay.io/biocontainers/bioconductor-proloc:1.50.0--r45ha27e39d_0
// R packages: MSnbase, pRoloc
// Bioconductor: 3.20 | R: 4.4
// Requires: MSnbase, pRoloc
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load User Input Data
//  * 2. [Visualization & Output] Calculate resolution metrics using QSep
//  * 3. [Visualization & Output] Visualize resolution distances using levelPlot and plot
//  * 4. [Visualization & Output] Convert standard marker character vector into binary
//  * 5. [Visualization & Output] Compute normalized pairwise Euclidean distances
//  * 6. [Visualization & Output] Plot the normalized distances

nextflow.enable.dsl = 2

process BIOC_PROLOC_SUBCELLULAR_RESOLUTION_ASSESSMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("MSnbase", "pRoloc")
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
        library(pRoloc)
        library(MSnbase)
        
        # -------------------------------------------------------------------------
        # --- Load User Input Data ---
        # -------------------------------------------------------------------------
        # Read the spatial proteomics data from the working directory
        input_file <- "spatial_proteomics_data.rds"
        if (!file.exists(input_file)) {
          stop(paste("Required input file", input_file, "not found in the working directory."))
        }
        
        hyperLOPIT2015 <- readRDS(input_file)
        
        # -------------------------------------------------------------------------
        # --- Calculate resolution metrics using QSep ---
        # -------------------------------------------------------------------------
        hlq <- QSep(hyperLOPIT2015)
        
        # Save the QSep object
        saveRDS(hlq, "qsep_resolution_metrics.rds")
        
        # Try to export the distance matrix as a CSV file
        tryCatch({
          # QSep objects typically store the distance matrix in the 'object' or can be coerced
          if (is(hlq, "QSep")) {
            # The slot containing the matrix is usually 'qsep'
            qsep_matrix <- qsep(hlq)
            write.csv(qsep_matrix, "qsep_distance_matrix.csv", row.names = TRUE)
          }
        }, error = function(e) {
          warning("Could not export QSep distance matrix to CSV: ", e\$message)
        })
        
        # -------------------------------------------------------------------------
        # --- Visualize resolution distances using levelPlot and plot ---
        # -------------------------------------------------------------------------
        pdf("resolution_plots.pdf", width = 10, height = 8)
        levelPlot(hlq)
        plot(hlq)
        dev.off()
        
        # -------------------------------------------------------------------------
        # --- Convert standard marker character vector into binary ---
        # -------------------------------------------------------------------------
        hld <- mrkVecToMat(hyperLOPIT2015, fcol = "markers", mfcol = "MM")
        
        # Save the modified MSnSet object containing the binary marker matrix
        saveRDS(hld, "spatial_proteomics_binary_markers.rds")
        
        # -------------------------------------------------------------------------
        # --- Compute normalized pairwise Euclidean distances ---
        # -------------------------------------------------------------------------
        dd <- clustDist(hld, fcol = "MM", k = 1:3, n = 5, verbose = FALSE)
        
        # Save the ClustDistList object
        saveRDS(dd, "clust_dist_results.rds")
        
        # -------------------------------------------------------------------------
        # --- Plot the normalized distances ---
        # -------------------------------------------------------------------------
        pdf("cluster_tightness_plots.pdf", width = 10, height = 8)
        plot(dd)
        dev.off()
        
        cat("Pipeline completed successfully. Outputs generated:\n")
        cat("- qsep_resolution_metrics.rds\n")
        cat("- qsep_distance_matrix.csv (if applicable)\n")
        cat("- resolution_plots.pdf\n")
        cat("- spatial_proteomics_binary_markers.rds\n")
        cat("- clust_dist_results.rds\n")
        cat("- cluster_tightness_plots.pdf\n")

    writeLines(c(
        '"BIOC_PROLOC_SUBCELLULAR_RESOLUTION_ASSESSMENT":',
        paste0('    pRoloc: ', as.character(packageVersion('pRoloc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_subcellular_resolution_assessment.csv versions.yml
    """
}

workflow BIOC_PROLOC_SUBCELLULAR_RESOLUTION_ASSESSMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spatial_proteomics_data.rds ] ]

    main:
    BIOC_PROLOC_SUBCELLULAR_RESOLUTION_ASSESSMENT(ch_input)

    emit:
    tables   = BIOC_PROLOC_SUBCELLULAR_RESOLUTION_ASSESSMENT.out.tables
    plots    = BIOC_PROLOC_SUBCELLULAR_RESOLUTION_ASSESSMENT.out.plots
    objects  = BIOC_PROLOC_SUBCELLULAR_RESOLUTION_ASSESSMENT.out.objects
    versions = BIOC_PROLOC_SUBCELLULAR_RESOLUTION_ASSESSMENT.out.versions
}
