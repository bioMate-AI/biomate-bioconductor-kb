#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gg4way — gg4way_with_edger
// Compare two contrasts from an edgeR analysis using a 4-way plot.
// Input: rfit, contr.matrix
// Container: quay.io/biocontainers/bioconductor-gg4way:1.8.0--r45hdfd78af_0
// R packages: edgeR, gg4way, ggplot2, purrr
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR, gg4way, ggplot2, purrr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run edgeR differential expression for each contrast and combine results into a named list
//  * 2. [Visualization & Output] Generate the 4-way plot using gg4way()

nextflow.enable.dsl = 2

process BIOC_GG4WAY_GG4WAY_WITH_EDGER {
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
    .bm_deps <- c("edgeR", "gg4way", "ggplot2", "purrr")
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
        library(edgeR)
        library(purrr)
        library(gg4way)
        library(ggplot2)
        
        # Read user inputs from the working directory
        rfit_path <- "rfit"
        if (!file.exists(rfit_path)) {
          rfit_path <- "rfit.rds"
        }
        
        contr_path <- "contr.matrix"
        if (!file.exists(contr_path)) {
          contr_path <- "contr.matrix.rds"
        }
        
        rfit <- readRDS(rfit_path)
        contr.matrix <- readRDS(contr_path)
        
        # Execute the documented workflow
        rfit <- contr.matrix |> 
            colnames() |>
            set_names() |>
            map(~ rfit |>
                    glmQLFTest(contrast = contr.matrix[,.x]))
        
        contrast_names <- colnames(contr.matrix)
        p1 <- rfit |>
            gg4way(x = contrast_names[1],
                   y = contrast_names[2])
        
        # Save the 4-way plot
        ggsave("gg4way_edgeR_plot.pdf", plot = p1, width = 6, height = 6.5)
        
        # Extract and save shared significant genes
        tryCatch({
          shared_df <- getShared(p1)
          write.csv(shared_df, "shared_genes.csv", row.names = FALSE)
        }, error = function(e) {
          warning("Could not extract shared genes: ", e\$message)
        })
        
        # Extract and save correlation coefficient
        tryCatch({
          corr_val <- getCor(p1)
          writeLines(as.character(corr_val), "correlation.txt")
        }, error = function(e) {
          warning("Could not extract correlation: ", e\$message)
        })

    writeLines(c(
        '"BIOC_GG4WAY_GG4WAY_WITH_EDGER":',
        paste0('    gg4way: ', as.character(packageVersion('gg4way')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gg4way_with_edger.csv versions.yml
    """
}

workflow BIOC_GG4WAY_GG4WAY_WITH_EDGER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rfit, contr.matrix ] ]

    main:
    BIOC_GG4WAY_GG4WAY_WITH_EDGER(ch_input)

    emit:
    tables   = BIOC_GG4WAY_GG4WAY_WITH_EDGER.out.tables
    plots    = BIOC_GG4WAY_GG4WAY_WITH_EDGER.out.plots
    objects  = BIOC_GG4WAY_GG4WAY_WITH_EDGER.out.objects
    versions = BIOC_GG4WAY_GG4WAY_WITH_EDGER.out.versions
}
