#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GRmetrics — gr_metrics_case_c
// Calculate GR metrics and visualize scatterplots and boxplots from stacked treated and control measurements (Case C).
// Input: inputCaseC
// Container: quay.io/biocontainers/bioconductor-grmetrics:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GRmetrics, ggplot2, htmlwidgets
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load input data
//  * 2. [Core Analysis] Fit GR curves and calculate metrics using GRfit with Case C
//  * 3. [Visualization & Output] Visualize metrics using scatterplots with GRscatter
//  * 4. [Visualization & Output] Visualize metrics using boxplots with GRbox

nextflow.enable.dsl = 2

process BIOC_GRMETRICS_GR_METRICS_CASE_C {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("GRmetrics", "ggplot2", "htmlwidgets")
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
        library(GRmetrics)
        library(ggplot2)
        library(htmlwidgets)
        
        # ==========================================
        # 1. Load input data
        # ==========================================
        # Read the user-provided inputCaseC file from the working directory.
        # Supports CSV, TSV, or TXT formats.
        if (file.exists("inputCaseC.csv")) {
          inputCaseC <- read.csv("inputCaseC.csv", stringsAsFactors = FALSE)
        } else if (file.exists("inputCaseC.tsv")) {
          inputCaseC <- read.delim("inputCaseC.tsv", stringsAsFactors = FALSE)
        } else if (file.exists("inputCaseC.txt")) {
          inputCaseC <- read.delim("inputCaseC.txt", stringsAsFactors = FALSE)
        } else {
          stop("Error: Required input file 'inputCaseC' (CSV, TSV, or TXT) not found in the working directory.")
        }
        
        # Ensure input is a data frame
        inputCaseC <- as.data.frame(inputCaseC)
        
        # ==========================================
        # 2. Fit GR curves and calculate metrics
        # ==========================================
        output1 = GRfit(inputData = inputCaseC, groupingVariables = c('cell_line','agent', 'perturbation', 'replicate', 'time'), case = "C")
        
        # Save the fitted SummarizedExperiment object
        saveRDS(output1, file = "GRfit_output.rds")
        
        # Extract and save GR metrics table
        metrics_df <- GRgetMetrics(output1)
        write.csv(metrics_df, file = "GRmetrics_results.csv", row.names = FALSE)
        
        # Extract and save original data with GR values
        values_df <- GRgetValues(output1)
        write.csv(values_df, file = "GRvalues_results.csv", row.names = FALSE)
        
        # ==========================================
        # 3. Visualize metrics using scatterplots and boxplots
        # ==========================================
        
        # Extract dynamic levels for plotting to avoid hardcoded errors
        agents <- as.character(na.omit(unique(inputCaseC\$agent)))
        if (length(agents) >= 3) {
          xaxis_agents <- agents[1:2]
          yaxis_agent <- agents[3]
        } else if (length(agents) == 2) {
          xaxis_agents <- agents[1]
          yaxis_agent <- agents[2]
        } else {
          xaxis_agents <- agents[1]
          yaxis_agent <- agents[1]
        }
        
        cell_lines <- as.character(na.omit(unique(inputCaseC\$cell_line)))
        if (length(cell_lines) >= 3) {
          box_factors <- cell_lines[1:2]
          wilA_cl <- cell_lines[1]
          wilB_cl <- cell_lines[2:3]
        } else if (length(cell_lines) == 2) {
          box_factors <- cell_lines[1:2]
          wilA_cl <- cell_lines[1]
          wilB_cl <- cell_lines[2]
        } else {
          box_factors <- cell_lines[1]
          wilA_cl <- cell_lines[1]
          wilB_cl <- cell_lines[1]
        }
    
        # Open PDF device to save static plots
        pdf("GRmetrics_plots.pdf", width = 10, height = 8)
        
        # We wrap the static (plotly = FALSE) plots in print() to ensure they render to the PDF device.
        # The interactive (plotly = TRUE) plots are executed as documented.
        
        # Documented Call 1 (Interactive Scatterplot)
        tryCatch({
          p_scatter_int <- GRscatter(output1, 'GR50', 'agent', xaxis_agents, yaxis_agent)
          saveWidget(p_scatter_int, "GRscatter_interactive.html", selfcontained = TRUE)
        }, error = function(e) {
          warning("Interactive GRscatter failed to render: ", e\$message)
        })
        
        # Documented Call 2 (Static Scatterplot)
        p_scatter_static <- GRscatter(output1, 'GR50', 'agent', xaxis_agents, yaxis_agent, plotly = FALSE)
        print(p_scatter_static)
        
        # Documented Call 3 (Interactive Boxplot)
        tryCatch({
          p_box_int1 <- GRbox(output1, metric ='GRinf', groupVariable = 'cell_line', pointColor = 'agent')
          saveWidget(p_box_int1, "GRbox_interactive1.html", selfcontained = TRUE)
        }, error = function(e) {
          warning("Interactive GRbox failed to render: ", e\$message)
        })
        
        # Documented Call 4 (Interactive Boxplot with factors)
        tryCatch({
          p_box_int2 <- GRbox(output1, metric ='GRinf', groupVariable = 'cell_line', pointColor = 'agent', factors = box_factors)
          saveWidget(p_box_int2, "GRbox_interactive2.html", selfcontained = TRUE)
        }, error = function(e) {
          warning("Interactive GRbox with factors failed to render: ", e\$message)
        })
        
        # Documented Call 5 (Static Boxplot with factors)
        p_box_static1 <- GRbox(output1, metric ='GRinf', groupVariable = 'cell_line', pointColor = 'agent', factors = box_factors, plotly = FALSE)
        print(p_box_static1)
        
        # Documented Call 6 (Static Boxplot with Wilcoxon comparison)
        p_box_static2 <- GRbox(output1, metric ='GR50', groupVariable = 'cell_line', pointColor = 'agent', wilA = wilA_cl, wilB = wilB_cl, plotly = FALSE)
        print(p_box_static2)
        
        # Close the PDF device
        dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_GRMETRICS_GR_METRICS_CASE_C",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GRMETRICS_GR_METRICS_CASE_C":',
        paste0('    GRmetrics: ', as.character(packageVersion('GRmetrics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gr_metrics_case_c.csv versions.yml
    """
}

workflow BIOC_GRMETRICS_GR_METRICS_CASE_C_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ inputCaseC ] ]

    main:
    BIOC_GRMETRICS_GR_METRICS_CASE_C(ch_input)

    emit:
    tables   = BIOC_GRMETRICS_GR_METRICS_CASE_C.out.tables
    plots    = BIOC_GRMETRICS_GR_METRICS_CASE_C.out.plots
    objects  = BIOC_GRMETRICS_GR_METRICS_CASE_C.out.objects
    versions = BIOC_GRMETRICS_GR_METRICS_CASE_C.out.versions
}
