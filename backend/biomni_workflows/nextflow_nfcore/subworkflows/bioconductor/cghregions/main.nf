#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CGHregions — cgh_dimension_reduction
// Reduce segmented and called array CGH data into genomic regions of minimal information loss and visualize the results.
// Input: called_cgh_data.RData
// Container: quay.io/biocontainers/bioconductor-cghregions:1.68.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, CGHregions
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and input data
//  * 2. [Core Analysis] Run the CGHregions dimension reduction algorithm
//  * 3. [Visualization & Output] Inspect and plot the resulting genomic regions

nextflow.enable.dsl = 2

process BIOC_CGHREGIONS_CGH_DIMENSION_REDUCTION {
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
    .bm_deps <- c("CGHregions", "Biobase")
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
    
    # 1. Load the package and input data
    library(CGHregions)
    library(Biobase)
    
    # Load the user input file
    input_file <- "called_cgh_data.RData"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Load the RData file into a temporary environment to locate the cghCall object
    temp_env <- new.env()
    load(input_file, envir = temp_env)
    
    # Find the object of class 'cghCall'
    obj_names <- ls(temp_env)
    cgh_obj_name <- NULL
    for (name in obj_names) {
      if (inherits(temp_env[[name]], "cghCall")) {
        cgh_obj_name <- name
        break
      }
    }
    
    if (is.null(cgh_obj_name)) {
      stop("No object of class 'cghCall' found in the loaded RData file.")
    }
    
    # Assign to the variable name used in the documented code
    WiltingCalled <- temp_env[[cgh_obj_name]]
    WiltingCalled
    
    # 2. Run the CGHregions dimension reduction algorithm
    regions <- CGHregions(WiltingCalled, averror=0.01)
    regions
    
    # 3. Inspect and plot the resulting genomic regions
    pdf("regions_plot.pdf", width = 10, height = 8)
    plot(regions)
    dev.off()
    
    # Save the resulting regions object
    saveRDS(regions, file = "regions.rds")
    
    # Export the region features (metadata) to a CSV file
    if (length(fData(regions)) > 0) {
      write.csv(fData(regions), file = "regions_features.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_CGHREGIONS_CGH_DIMENSION_REDUCTION":',
        paste0('    CGHregions: ', as.character(packageVersion('CGHregions')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cgh_dimension_reduction.csv versions.yml
    """
}

workflow BIOC_CGHREGIONS_CGH_DIMENSION_REDUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ called_cgh_data.RData ] ]

    main:
    BIOC_CGHREGIONS_CGH_DIMENSION_REDUCTION(ch_input)

    emit:
    tables   = BIOC_CGHREGIONS_CGH_DIMENSION_REDUCTION.out.tables
    plots    = BIOC_CGHREGIONS_CGH_DIMENSION_REDUCTION.out.plots
    objects  = BIOC_CGHREGIONS_CGH_DIMENSION_REDUCTION.out.objects
    versions = BIOC_CGHREGIONS_CGH_DIMENSION_REDUCTION.out.versions
}
