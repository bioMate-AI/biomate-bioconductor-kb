#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gg4way — gg4way_with_deseq2
// Compare two contrasts from a DESeq2 analysis using a 4-way plot (supporting results names, custom contrasts, or lfcShrink).
// Input: dds
// Container: quay.io/biocontainers/bioconductor-gg4way:1.8.0--r45hdfd78af_0
// R packages: DESeq2, gg4way, ggplot2, purrr
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, gg4way, ggplot2, purrr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Generate 4-way plot directly from DESeqDataSet using results names
//  * 2. [Visualization & Output] Alternatively, generate 4-way plot from a named list of DESeqResults objects using results()
//  * 3. [Visualization & Output] Alternatively, generate 4-way plot from a named list of shrunken log fold changes using lfcShrink()

nextflow.enable.dsl = 2

process BIOC_GG4WAY_GG4WAY_WITH_DESEQ2 {
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
    .bm_deps <- c("DESeq2", "gg4way", "ggplot2", "purrr")
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
        library(DESeq2)
        library(purrr)
        library(gg4way)
        library(ggplot2)
        
        # Read user input
        if (file.exists("dds")) {
          dds <- readRDS("dds")
        } else if (file.exists("dds.rds")) {
          dds <- readRDS("dds.rds")
        } else {
          stop("Error: Input file 'dds' or 'dds.rds' not found in the working directory.")
        }
        
        # Extract valid results names dynamically
        res_names <- resultsNames(dds)
        res_names <- res_names[res_names != "Intercept"]
        
        if (length(res_names) < 2) {
          stop("Error: dds must have at least two non-Intercept resultsNames to generate a 4-way plot.")
        }
        
        x_name <- res_names[1]
        y_name <- res_names[2]
        
        # Create a named list for mapping
        res_list <- setNames(list(x_name, y_name), c(x_name, y_name))
        
        # Stage 1: Generate 4-way plot directly from DESeqDataSet using results names
        p1 <- dds |>
            gg4way(x = x_name,
                   y = y_name)
        
        ggsave("gg4way_results_names.pdf", plot = p1, width = 6, height = 6.5)
        
        # Extract and save meaningful tables from the first plot
        tryCatch({
          shared_genes <- getShared(p1)
          write.csv(shared_genes, "shared_genes.csv", row.names = FALSE)
        }, error = function(e) {
          message("Could not extract shared genes: ", e\$message)
        })
        
        tryCatch({
          totals <- getTotals(p1)
          write.csv(totals, "totals.csv", row.names = FALSE)
        }, error = function(e) {
          message("Could not extract totals: ", e\$message)
        })
        
        # Stage 2: Generate 4-way plot from a named list of DESeqResults objects using results()
        p2 <- res_list |>
            map(~ results(dds, name = .x)) |>
            gg4way(x = x_name,
                   y = y_name)
        
        ggsave("gg4way_contrast.pdf", plot = p2, width = 6, height = 6.5)
        
        # Stage 3: Generate 4-way plot from a named list of shrunken log fold changes using lfcShrink()
        p3 <- res_list |>
            map(~ dds |>
                results(name = .x) |>
                lfcShrink(dds, coef = .x, res = _, type = "normal")) |>
            gg4way(x = x_name,
                   y = y_name)
        
        ggsave("gg4way_lfcShrink.pdf", plot = p3, width = 6, height = 6.5)

    writeLines(c(
        '"BIOC_GG4WAY_GG4WAY_WITH_DESEQ2":',
        paste0('    gg4way: ', as.character(packageVersion('gg4way')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gg4way_with_deseq2.csv versions.yml
    """
}

workflow BIOC_GG4WAY_GG4WAY_WITH_DESEQ2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dds ] ]

    main:
    BIOC_GG4WAY_GG4WAY_WITH_DESEQ2(ch_input)

    emit:
    tables   = BIOC_GG4WAY_GG4WAY_WITH_DESEQ2.out.tables
    plots    = BIOC_GG4WAY_GG4WAY_WITH_DESEQ2.out.plots
    objects  = BIOC_GG4WAY_GG4WAY_WITH_DESEQ2.out.objects
    versions = BIOC_GG4WAY_GG4WAY_WITH_DESEQ2.out.versions
}
