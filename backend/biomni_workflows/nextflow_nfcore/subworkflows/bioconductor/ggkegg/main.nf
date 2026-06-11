#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggkegg — kegg_module_visualization
// Parse a KEGG module and visualize it using text-based or network-based representations.
// Input: M00002
// Container: quay.io/biocontainers/bioconductor-ggkegg:1.8.0--r45hdfd78af_0
// R packages: dplyr, ggkegg, ggplot2, tidygraph
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGKEGG_KEGG_MODULE_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ggkegg:1.8.0--r45hdfd78af_0"

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
    .bm_deps <- c("dplyr", "ggkegg", "ggplot2", "tidygraph")
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
    library(ggkegg)
    library(tidygraph)
    library(dplyr)
    library(ggplot2)
    
    # Read the user input file 'M00002' to get the KEGG Module ID
    input_file <- "M00002"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Read the ID from the file. If the file is empty, use the filename itself.
    file_content <- readLines(input_file, warn = FALSE)
    module_id <- if (length(file_content) > 0 && nchar(trimws(file_content[1])) > 0) {
      trimws(file_content[1])
    } else {
      basename(input_file)
    }
    
    # 1. Retrieve and parse the KEGG module
    mod <- module(module_id, use_cache=TRUE)
    
    # Save the parsed module object
    saveRDS(mod, "kegg_module.rds")
    
    # 2. Generate a text-based module visualization
    mod_text_df <- mod |>
        module_text() ## return data.frame
    
    # Save the text-based data frame
    write.csv(mod_text_df, "module_text_data.csv", row.names = FALSE)
    
    # Plot the text-based module
    p_text <- mod_text_df |>
        plot_module_text()
    
    # Save the text-based plot
    ggplot2::ggsave("module_text_plot.pdf", plot = p_text, width = 8, height = 4)
    
    # 3. Generate a network-based module block visualization
    mod_graph <- mod |>
        obtain_sequential_module_definition() ## return tbl_graph
    
    # Save the tbl_graph object
    saveRDS(mod_graph, "module_graph.rds")
    
    # Plot the module blocks
    p_blocks <- mod_graph |>
        plot_module_blocks()
    
    # Save the network-based plot
    ggplot2::ggsave("module_blocks_plot.pdf", plot = p_blocks, width = 8, height = 8)

    writeLines(c(
        '"BIOC_GGKEGG_KEGG_MODULE_VISUALIZATION":',
        paste0('        ggkegg: ', as.character(packageVersion("ggkegg")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_kegg_module_visualization.csv versions.yml
    """
}

workflow BIOC_GGKEGG_KEGG_MODULE_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ M00002 ] ]

    main:
    BIOC_GGKEGG_KEGG_MODULE_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_GGKEGG_KEGG_MODULE_VISUALIZATION.out.tables
    plots    = BIOC_GGKEGG_KEGG_MODULE_VISUALIZATION.out.plots
    objects  = BIOC_GGKEGG_KEGG_MODULE_VISUALIZATION.out.objects
    versions = BIOC_GGKEGG_KEGG_MODULE_VISUALIZATION.out.versions
}
