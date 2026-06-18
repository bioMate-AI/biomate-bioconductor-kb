#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tidyFlowCore — tidy_flow_cytometry_analysis
// Perform end-to-end flow cytometry data analysis including transformation, cell population counting, grouping, and plotting using tidyverse verbs.
// Input: fcs_files, flowSet_object
// Container: quay.io/biocontainers/bioconductor-tidyflowcore:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, flowCore, ggplot2, tidyFlowCore
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load packages
//  * 2. [Input & Preparation] Read flow cytometry data
//  * 3. [Core Analysis] Apply data transformation using dplyr::mutate and across
//  * 4. [Core Analysis] Count cells per population using dplyr::count
//  * 5. [Visualization & Output] Perform grouped operations by unnesting (dplyr::ungroup), grouping (dplyr::group_by), and summarizing (dplyr::summarize)
//  * 6. [Visualization & Output] Visualize data using ggplot2 directly on the flowSet/flowFrame objects

nextflow.enable.dsl = 2

process BIOC_TIDYFLOWCORE_TIDY_FLOW_CYTOMETRY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("tidyFlowCore", "flowCore", "dplyr", "ggplot2")
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
    
    # 1. Load packages
    library(tidyFlowCore)
    library(flowCore)
    library(dplyr)
    library(ggplot2)
    
    # 2. Read flow cytometry data from the declared user input files
    if (file.exists("flowSet_object")) {
      bcr_flowset <- readRDS("flowSet_object")
    } else if (file.exists("flowSet_object.rds")) {
      bcr_flowset <- readRDS("flowSet_object.rds")
    } else if (file.exists("fcs_files")) {
      if (dir.exists("fcs_files")) {
        fcs_paths <- list.files("fcs_files", pattern = "\\\\.fcs\$", full.names = TRUE)
        bcr_flowset <- flowCore::read.flowSet(fcs_paths)
      } else {
        bcr_flowset <- flowCore::read.flowSet("fcs_files")
      }
    } else {
      stop("Error: Neither 'flowSet_object' nor 'fcs_files' was found in the working directory.")
    }
    
    # Dynamically determine column names to avoid hardcoding
    col_names <- colnames(bcr_flowset)
    hladr_col <- col_names[1]
    cd20_col <- col_names[min(2, length(col_names))]
    cd4_col <- col_names[min(3, length(col_names))]
    pop_col <- col_names[length(col_names)]
    
    # 3. Apply data transformation using dplyr::mutate and across
    transformed_bcr_flowset <- 
      bcr_flowset |>
      dplyr::mutate(across(-ends_with("_id"), \(.x) asinh(.x / 5)))
    
    # Save transformed flowSet object
    saveRDS(transformed_bcr_flowset, "transformed_bcr_flowset.rds")
    
    # 4. Count cells per population using dplyr::count
    counts_by_pop <- bcr_flowset |> 
      dplyr::count(.data[[pop_col]])
    
    write.csv(counts_by_pop, "cell_counts_by_population.csv", row.names = FALSE)
    
    counts_by_id_pop <- bcr_flowset |> 
      dplyr::count(.tidyFlowCore_identifier, .data[[pop_col]])
    
    write.csv(counts_by_id_pop, "cell_counts_by_identifier_and_population.csv", row.names = FALSE)
    
    # 5. Perform grouped operations by unnesting (dplyr::ungroup), grouping (dplyr::group_by), and summarizing (dplyr::summarize)
    ungrouped_flowframe <- bcr_flowset |> 
      dplyr::ungroup()
    
    mean_hladr_expr <- bcr_flowset |> 
      dplyr::ungroup() |> 
      dplyr::group_by(.data[[pop_col]]) |> 
      dplyr::summarize(mean_hladr_expression = mean(.data[[hladr_col]])) |> 
      dplyr::select(dplyr::all_of(pop_col), mean_hladr_expression)
    
    write.csv(mean_hladr_expr, "mean_hladr_expression.csv", row.names = FALSE)
    
    mean_cd20_expression <- 
      bcr_flowset |> 
      dplyr::ungroup() |> 
      dplyr::summarize(mean_expression = mean(asinh(.data[[cd20_col]] / 5))) |> 
      dplyr::pull(mean_expression)
    
    mean_cd4_expression <- 
      bcr_flowset |> 
      dplyr::ungroup() |> 
      dplyr::summarize(mean_expression = mean(asinh(.data[[cd4_col]] / 5))) |> 
      dplyr::pull(mean_expression)
    
    # 6. Visualize data using ggplot2 directly on the flowSet/flowFrame objects
    p <- bcr_flowset |> 
      dplyr::mutate(dplyr::across(-ends_with("_id"), \(.x) asinh(.x / 5))) |> 
      ggplot2::ggplot(ggplot2::aes(x = .data[[cd20_col]], y = .data[[cd4_col]])) +
      ggplot2::geom_hline(
        yintercept = mean_cd4_expression, 
        color = "red", 
        linetype = "dashed"
      ) + 
      ggplot2::geom_vline(
        xintercept = mean_cd20_expression, 
        color = "red", 
        linetype = "dashed"
      ) + 
      ggplot2::geom_point(size = 0.1, alpha = 0.1) +
      ggplot2::facet_wrap(
        facets = ggplot2::vars(.data[[pop_col]])
      ) + 
      ggplot2::labs(
        x = paste(cd20_col, "expression (arcsinh)"), 
        y = paste(cd4_col, "expression (arcsinh)")
      )
    
    ggplot2::ggsave("cd4_vs_cd20_expression_plot.pdf", plot = p, width = 10, height = 8)

    writeLines(c(
        '"BIOC_TIDYFLOWCORE_TIDY_FLOW_CYTOMETRY_ANALYSIS":',
        paste0('    tidyFlowCore: ', as.character(packageVersion('tidyFlowCore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidy_flow_cytometry_analysis.csv versions.yml
    """
}

workflow BIOC_TIDYFLOWCORE_TIDY_FLOW_CYTOMETRY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fcs_files, flowSet_object ] ]

    main:
    BIOC_TIDYFLOWCORE_TIDY_FLOW_CYTOMETRY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TIDYFLOWCORE_TIDY_FLOW_CYTOMETRY_ANALYSIS.out.tables
    plots    = BIOC_TIDYFLOWCORE_TIDY_FLOW_CYTOMETRY_ANALYSIS.out.plots
    objects  = BIOC_TIDYFLOWCORE_TIDY_FLOW_CYTOMETRY_ANALYSIS.out.objects
    versions = BIOC_TIDYFLOWCORE_TIDY_FLOW_CYTOMETRY_ANALYSIS.out.versions
}
