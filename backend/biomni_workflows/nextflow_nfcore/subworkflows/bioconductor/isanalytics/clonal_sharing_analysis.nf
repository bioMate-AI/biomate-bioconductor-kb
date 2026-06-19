#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ISAnalytics — clonal_sharing_analysis
// Identify shared integration sites across different groups or samples and visualize them using heatmaps or Venn/Euler diagrams.
// Input: integration_matrices, association_file
// Container: quay.io/biocontainers/bioconductor-isanalytics:1.20.1--r45hdfd78af_0
// R packages: ISAnalytics, dplyr, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: ISAnalytics, dplyr, ggplot2
// Visualizations: heatmap, Venn diagram
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Aggregate matrix values by key using aggregate_values_by_key()
//  * 2. [Core Analysis] Filter the aggregated data for specific groups of interest
//  * 3. [Core Analysis] Compute sharing counts and relative sharing percentages using is_sharing()
//  * 4. [Visualization & Output] Plot sharing heatmaps using sharing_heatmap()
//  * 5. [Visualization & Output] Generate Venn or Euler diagrams using sharing_venn() and plot()

nextflow.enable.dsl = 2

process BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS {
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
    .bm_deps <- c("ISAnalytics", "dplyr", "ggplot2")
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
            library(ISAnalytics)
            library(dplyr)
            library(ggplot2)
            
            # Helper function to load user inputs robustly
            load_input <- function(base_name) {
              if (file.exists(base_name)) {
                return(readRDS(base_name))
              } else if (file.exists(paste0(base_name, ".rds"))) {
                return(readRDS(paste0(base_name, ".rds")))
              } else if (file.exists(paste0(base_name, ".RData"))) {
                env <- new.env()
                load(paste0(base_name, ".RData"), envir = env)
                objs <- ls(env)
                if (base_name %in% objs) {
                  return(env[[base_name]])
                } else {
                  return(env[[objs[1]]])
                }
              } else {
                stop(paste("Required input file not found in the working directory:", base_name))
              }
            }
            
            # 1. Load User Inputs
            integration_matrices <- load_input("integration_matrices")
            association_file <- load_input("association_file")
            
            # 2. Aggregate matrix values by key
            agg <- aggregate_values_by_key(integration_matrices,
                association_file,
                value_cols = c("seqCount", "fragmentEstimate"),
                key = c("SubjectID", "CellMarker", "Tissue", "TimePoint")
            )
            
            # 3. Filter the aggregated data for specific groups of interest
            if (is.data.frame(agg)) {
              agg <- agg |> dplyr::filter(TimePoint %in% c("0030", "0060"))
            } else if (is.list(agg)) {
              agg <- lapply(agg, function(x) x |> dplyr::filter(TimePoint %in% c("0030", "0060")))
            }
            
            # 4. Compute sharing counts and relative sharing percentages (minimal = TRUE)
            sharing_1 <- is_sharing(agg,
                group_keys = c(
                    "SubjectID", "CellMarker",
                    "Tissue", "TimePoint"
                ),
                n_comp = 2,
                is_count = TRUE,
                relative_is_sharing = TRUE,
                minimal = TRUE,
                include_self_comp = FALSE,
                keep_genomic_coord = TRUE
            )
            
            # 5. Compute sharing counts and relative sharing percentages (minimal = FALSE)
            sharing_1_b <- is_sharing(agg,
                group_keys = c(
                    "SubjectID", "CellMarker",
                    "Tissue", "TimePoint"
                ),
                n_comp = 2,
                is_count = TRUE,
                relative_is_sharing = TRUE,
                minimal = FALSE,
                include_self_comp = TRUE
            )
            
            # 6. Plot sharing heatmaps
            heatmaps <- sharing_heatmap(sharing_1_b)
            
            # 7. Compute sharing for Venn/Euler diagrams
            sharing_5 <- is_sharing(agg,
                group_keys = c(
                    "SubjectID", "CellMarker",
                    "Tissue", "TimePoint"
                ), table_for_venn = TRUE
            )
            
            # 8. Generate Venn or Euler diagrams
            sharing_plots1 <- sharing_venn(sharing_5, row_range = 1, euler = TRUE)
            
            # 9. Save Outputs to Working Directory
            # Save data tables
            saveRDS(sharing_1, "sharing_minimal.rds")
            if (is.data.frame(sharing_1)) {
              write.csv(sharing_1, "sharing_minimal.csv", row.names = FALSE)
            }
            
            saveRDS(sharing_1_b, "sharing_full.rds")
            if (is.data.frame(sharing_1_b)) {
              write.csv(sharing_1_b, "sharing_full.csv", row.names = FALSE)
            }
            
            saveRDS(sharing_5, "sharing_venn_table.rds")
            if (is.data.frame(sharing_5)) {
              write.csv(sharing_5, "sharing_venn_table.csv", row.names = FALSE)
            }
            
            # Save Heatmap Plots
            pdf("sharing_heatmaps.pdf", width = 10, height = 8)
            if (inherits(heatmaps, "list")) {
              for (p in heatmaps) {
                if (inherits(p, "ggplot") || inherits(p, "gtable") || inherits(p, "ggplot_gtable")) {
                  print(p)
                } else {
                  tryCatch(plot(p), error = function(e) NULL)
                }
              }
            } else {
              print(heatmaps)
            }
            dev.off()
            
            # Save Venn/Euler Plots
            pdf("sharing_venn_plots.pdf", width = 8, height = 8)
            if (length(sharing_plots1) >= 1) {
              plot(sharing_plots1[[1]])
            }
            dev.off()

    writeLines(c(
        '"BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS":',
        paste0('    ISAnalytics: ', as.character(packageVersion('ISAnalytics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clonal_sharing_analysis.csv versions.yml
    """
}

workflow BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ integration_matrices, association_file ] ]

    main:
    BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS.out.tables
    plots    = BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS.out.plots
    objects  = BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS.out.objects
    versions = BIOC_ISANALYTICS_CLONAL_SHARING_ANALYSIS.out.versions
}
