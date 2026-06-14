#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tpSVG — poisson_count_model
// Detect spatially variable genes from raw count spatially resolved transcriptomics data using a Poisson model.
// Input: spe
// Container: quay.io/biocontainers/bioconductor-tpsvg:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, tpSVG
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate the library size (total counts) per spot/cell
//  * 2. [Core Analysis] Run tpSVG with a Poisson family, specifying the raw counts assay and the log-transformed library size as an offset
//  * 3. [Core Analysis] Retrieve the SVG statistics and p-values from the rowData of the returned object

nextflow.enable.dsl = 2

process BIOC_TPSVG_POISSON_COUNT_MODEL {
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
    .bm_deps <- c("tpSVG", "SpatialExperiment", "SummarizedExperiment")
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
    library(tpSVG)
    library(SummarizedExperiment)
    library(SpatialExperiment)
    
    # 1. Read the input SpatialExperiment object from the working directory
    if (!file.exists("spe.rds")) {
      stop("Error: Input file 'spe.rds' not found in the working directory.")
    }
    spe <- readRDS("spe.rds")
    
    # 2. Calculate the library size (total counts) per spot/cell
    spe\$total <- counts(spe) |> colSums()
    
    # 3. Run tpSVG with a Poisson family, specifying the raw counts assay and the log-transformed library size as an offset
    set.seed(1)
    spe_poisson  <- tpSVG(
      spe,
      family = poisson,
      assay_name = "counts",
      offset = log(spe\$total)   # Natural log library size
    )
    
    # 4. Retrieve the SVG statistics and p-values from the rowData of the returned object
    svg_results <- rowData(spe_poisson)
    
    # 5. Write named output files for the meaningful results
    # Save the updated SpatialExperiment object containing the tpSVG results
    saveRDS(spe_poisson, "spe_poisson.rds")
    
    # Save the SVG statistics and p-values as a CSV table
    write.csv(as.data.frame(svg_results), "tpSVG_poisson_results.csv", row.names = TRUE)
    
    message("tpSVG Poisson workflow completed successfully.")
    message("Outputs saved: 'spe_poisson.rds' and 'tpSVG_poisson_results.csv'.")

    writeLines(c(
        '"BIOC_TPSVG_POISSON_COUNT_MODEL":',
        paste0('    tpSVG: ', as.character(packageVersion('tpSVG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_poisson_count_model.csv versions.yml
    """
}

workflow BIOC_TPSVG_POISSON_COUNT_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe ] ]

    main:
    BIOC_TPSVG_POISSON_COUNT_MODEL(ch_input)

    emit:
    tables   = BIOC_TPSVG_POISSON_COUNT_MODEL.out.tables
    plots    = BIOC_TPSVG_POISSON_COUNT_MODEL.out.plots
    objects  = BIOC_TPSVG_POISSON_COUNT_MODEL.out.objects
    versions = BIOC_TPSVG_POISSON_COUNT_MODEL.out.versions
}
