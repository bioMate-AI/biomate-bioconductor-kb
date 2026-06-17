#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sccomp — random_effects_modeling
// Model cell-type proportions with both fixed effects and random effects (e.g., random intercepts or random slopes).
// Input: user_seurat_obj.rds
// Container: quay.io/biocontainers/bioconductor-sccomp:2.2.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, dplyr, ggplot2, readr, sccomp
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate composition using sccomp_estimate() with random effects syntax in formula_composition

nextflow.enable.dsl = 2

process BIOC_SCCOMP_RANDOM_EFFECTS_MODELING {
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
    .bm_deps <- c("dplyr", "sccomp", "Seurat", "readr", "ggplot2")
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
    library(dplyr)
    library(sccomp)
    library(Seurat)
    library(readr)
    library(ggplot2)
    
    # Define input file path
    input_file <- "user_seurat_obj.rds"
    
    # Check if the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the user-provided Seurat object
    seurat_obj <- readRDS(input_file)
    
    # Run the sccomp estimation with random effects as documented
    res =
      seurat_obj |>
      sccomp_estimate(
          formula_composition = ~ type + (type | group__) + (1 | group2__),
          sample = "sample",
          cell_group = "cell_group",
          bimodal_mean_variability_association = TRUE,
          cores = 1, verbose = FALSE
        )
    
    # Save the complete results object as an RDS file
    saveRDS(res, "sccomp_random_effects_results.rds")
    
    # Export a flattened version of the results table to CSV (excluding nested list-columns)
    res_flat <- as_tibble(res) %>% 
      select(where(is.atomic))
    
    write_csv(res_flat, "sccomp_random_effects_results.csv")
    
    # Attempt to generate and save diagnostic plots if applicable
    tryCatch({
      p_box <- res |> sccomp_boxplot(factor = "type")
      ggsave("sccomp_boxplot.pdf", plot = p_box, width = 10, height = 8)
    }, error = function(e) {
      message("Note: Could not generate boxplot. ", e\$message)
    })

    writeLines(c(
        '"BIOC_SCCOMP_RANDOM_EFFECTS_MODELING":',
        paste0('    sccomp: ', as.character(packageVersion('sccomp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_random_effects_modeling.csv versions.yml
    """
}

workflow BIOC_SCCOMP_RANDOM_EFFECTS_MODELING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_seurat_obj.rds ] ]

    main:
    BIOC_SCCOMP_RANDOM_EFFECTS_MODELING(ch_input)

    emit:
    tables   = BIOC_SCCOMP_RANDOM_EFFECTS_MODELING.out.tables
    plots    = BIOC_SCCOMP_RANDOM_EFFECTS_MODELING.out.plots
    objects  = BIOC_SCCOMP_RANDOM_EFFECTS_MODELING.out.objects
    versions = BIOC_SCCOMP_RANDOM_EFFECTS_MODELING.out.versions
}
