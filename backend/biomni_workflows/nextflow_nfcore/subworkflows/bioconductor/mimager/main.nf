#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mimager — raw_microarray_visualization
// Visualize raw probe-level intensities across one or more microarray chips to inspect for spatial artifacts.
// Input: raw_microarray_data.RData
// Container: quay.io/biocontainers/bioconductor-mimager:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, mimager
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the microarray data
//  * 2. [Visualization & Output] Visualize a single array
//  * 3. [Visualization & Output] Visualize multiple arrays in a grid layout
//  * 4. [Visualization & Output] Customize probe selection and row-filling options

nextflow.enable.dsl = 2

process BIOC_MIMAGER_RAW_MICROARRAY_VISUALIZATION {
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
    .bm_deps <- c("mimager", "Biobase")
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
    library(mimager)
    library(Biobase)
    
    # --- Load the microarray data ---
    load("raw_microarray_data.RData")
    
    # Identify the loaded microarray object dynamically
    objs <- ls()
    objs <- objs[!objs %in% c("objs")]
    Dilution <- NULL
    for (o in objs) {
      val <- get(o)
      if (inherits(val, c("AffyBatch", "ExpressionFeatureSet", "ExonFeatureSet", "GeneFeatureSet", "SnpFeatureSet"))) {
        Dilution <- val
        break
      }
    }
    if (is.null(Dilution)) {
      Dilution <- get(objs[1])
    }
    
    # --- Visualize a single array ---
    pdf("mimage_single.pdf", width = 7, height = 7)
    mimage(Dilution, select = 1)
    dev.off()
    
    # --- Visualize multiple arrays in a grid layout ---
    pdf("mimage_all.pdf", width = 10, height = 10)
    mimage(Dilution)
    dev.off()
    
    # --- Customize probe selection and row-filling options ---
    pdf("mimage_grid.pdf", width = 12, height = 4)
    mimage(Dilution, probes = "all", empty.rows = "ignore", nrow = 1)
    dev.off()
    
    # Save the processed object as RDS
    saveRDS(Dilution, file = "processed_microarray_data.rds")

    writeLines(c(
        '"BIOC_MIMAGER_RAW_MICROARRAY_VISUALIZATION":',
        paste0('    mimager: ', as.character(packageVersion('mimager')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_raw_microarray_visualization.csv versions.yml
    """
}

workflow BIOC_MIMAGER_RAW_MICROARRAY_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_microarray_data.RData ] ]

    main:
    BIOC_MIMAGER_RAW_MICROARRAY_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_MIMAGER_RAW_MICROARRAY_VISUALIZATION.out.tables
    plots    = BIOC_MIMAGER_RAW_MICROARRAY_VISUALIZATION.out.plots
    objects  = BIOC_MIMAGER_RAW_MICROARRAY_VISUALIZATION.out.objects
    versions = BIOC_MIMAGER_RAW_MICROARRAY_VISUALIZATION.out.versions
}
