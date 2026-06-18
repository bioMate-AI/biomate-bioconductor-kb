#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowGraph — fast_flowgraph_subset_analysis
// Perform a fast differential cell population analysis on large datasets (>10,000 cell populations) with a single class comparison.
// Input: count, meta
// Container: quay.io/biocontainers/bioconductor-flowgraph:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowGraph
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Initialize flowGraph Object using flowGraphSubset
//  * 3. [Visualization & Output] Save Outputs and Generate Diagnostic Plots

nextflow.enable.dsl = 2

process BIOC_FLOWGRAPH_FAST_FLOWGRAPH_SUBSET_ANALYSIS {
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
    .bm_deps <- c("flowGraph")
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
        library(flowGraph)
        
        # -----------------------------------------------------------------------------
        # --- Read User Input Files ---
        # -----------------------------------------------------------------------------
        
        # Read count matrix (sample x cell population numeric matrix)
        if (file.exists("count.rds")) {
          count_mat <- readRDS("count.rds")
        } else if (file.exists("count.csv")) {
          count_mat <- as.matrix(read.csv("count.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("count.tsv")) {
          count_mat <- as.matrix(read.delim("count.tsv", row.names = 1, check.names = FALSE))
        } else {
          stop("Required input file 'count' (CSV/RDS/TSV) not found in the working directory.")
        }
        
        # Read metadata data frame
        if (file.exists("meta.rds")) {
          meta_df <- readRDS("meta.rds")
        } else if (file.exists("meta.csv")) {
          meta_df <- read.csv("meta.csv", check.names = FALSE)
        } else if (file.exists("meta.tsv")) {
          meta_df <- read.delim("meta.tsv", check.names = FALSE)
        } else {
          stop("Required input file 'meta' (CSV/RDS/TSV) not found in the working directory.")
        }
        
        # Ensure 'id' column exists in metadata and matches row names of count matrix
        if (!"id" %in% colnames(meta_df)) {
          if (!is.null(rownames(meta_df)) && all(rownames(meta_df) %in% rownames(count_mat))) {
            meta_df\$id <- rownames(meta_df)
          } else {
            stop("Metadata must contain an 'id' column matching the row names of the count matrix.")
          }
        }
        
        # Align count matrix rows with metadata ids
        common_samples <- intersect(rownames(count_mat), meta_df\$id)
        if (length(common_samples) == 0) {
          stop("No matching sample IDs found between count matrix row names and metadata 'id' column.")
        }
        count_mat <- count_mat[common_samples, , drop = FALSE]
        meta_df <- meta_df[match(common_samples, meta_df\$id), , drop = FALSE]
        
        # Set number of cores for parallel processing
        no_cores <- 1
        
        # -----------------------------------------------------------------------------
        # --- Initialize flowGraph Object using flowGraphSubset ---
        # -----------------------------------------------------------------------------
        
        fg <- flowGraphSubset(count_mat, meta=meta_df, no_cores=no_cores,
                         summary_pars=flowGraphSubset_summary_pars(),
                         summary_adjust=flowGraphSubset_summary_adjust())
        
        # -----------------------------------------------------------------------------
        # --- Save Outputs and Generate Diagnostic Plots ---
        # -----------------------------------------------------------------------------
        
        # Save the complete flowGraph object
        saveRDS(fg, file = "flowGraph_subset_object.rds")
        
        # Save summary descriptions
        sum_desc <- fg_get_summary_desc(fg)
        write.csv(sum_desc\$node, file = "node_summary_description.csv", row.names = FALSE)
        
        # Extract and save the primary summary statistics (p-values)
        tryCatch({
          fg_sum <- fg_get_summary(fg, type = "node", index = 1)
          p_values_df <- data.frame(
            phenotype = names(fg_sum\$values),
            p_value = fg_sum\$values,
            stringsAsFactors = FALSE
          )
          # Sort by significance
          p_values_df <- p_values_df[order(p_values_df\$p_value), ]
          write.csv(p_values_df, file = "differential_abundance_pvalues.csv", row.names = FALSE)
        }, error = function(e) {
          warning("Could not extract summary statistics: ", e\$message)
        })
        
        # Generate and save diagnostic plots
        tryCatch({
          pdf("diagnostic_plots.pdf", width = 8, height = 8)
          
          # QQ Plot
          message("Generating QQ plot...")
          print(fg_plot_qq(fg, type = "node", index = 1))
          
          # Volcano-like Plot (p-value vs feature difference)
          message("Generating p-value vs difference plot...")
          print(fg_plot_pVSdiff(fg, type = "node", index = 1))
          
          dev.off()
        }, error = function(e) {
          warning("Could not generate diagnostic plots: ", e\$message)
          if (dev.cur() > 1) dev.off()
        })
        
        # Generate and save cell hierarchy plot
        tryCatch({
          pdf("cell_hierarchy_plot.pdf", width = 12, height = 12)
          message("Generating cell hierarchy plot...")
          gr <- fg_plot(fg, index = 1, p_thres = 0.05, show_bgedges = TRUE)
          print(plot_gr(gr, main = "Cell Hierarchy - Significant Populations"))
          dev.off()
        }, error = function(e) {
          warning("Could not generate cell hierarchy plot: ", e\$message)
          if (dev.cur() > 1) dev.off()
        })
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_FLOWGRAPH_FAST_FLOWGRAPH_SUBSET_ANALYSIS":',
        paste0('    flowGraph: ', as.character(packageVersion('flowGraph')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fast_flowgraph_subset_analysis.csv versions.yml
    """
}

workflow BIOC_FLOWGRAPH_FAST_FLOWGRAPH_SUBSET_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count, meta ] ]

    main:
    BIOC_FLOWGRAPH_FAST_FLOWGRAPH_SUBSET_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FLOWGRAPH_FAST_FLOWGRAPH_SUBSET_ANALYSIS.out.tables
    plots    = BIOC_FLOWGRAPH_FAST_FLOWGRAPH_SUBSET_ANALYSIS.out.plots
    objects  = BIOC_FLOWGRAPH_FAST_FLOWGRAPH_SUBSET_ANALYSIS.out.objects
    versions = BIOC_FLOWGRAPH_FAST_FLOWGRAPH_SUBSET_ANALYSIS.out.versions
}
