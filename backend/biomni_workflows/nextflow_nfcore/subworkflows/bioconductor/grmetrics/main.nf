#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GRmetrics — gr_metrics_case_a
// Calculate GR metrics and visualize dose-response curves from data with pre-computed control and time 0 cell counts (Case A).
// Input: inputCaseA
// Container: quay.io/biocontainers/bioconductor-grmetrics:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GRmetrics
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load input data
//  * 2. [Core Analysis] Fit GR curves and calculate metrics using GRfit with Case A
//  * 3. [Core Analysis] Extract metrics table using GRgetMetrics
//  * 4. [Core Analysis] Extract original and calculated GR values using GRgetValues
//  * 5. [Core Analysis] Extract grouping variables using GRgetGroupVars
//  * 6. [Visualization & Output] Visualize dose-response curves using GRdrawDRC

nextflow.enable.dsl = 2

process BIOC_GRMETRICS_GR_METRICS_CASE_A {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required library
    library(GRmetrics)
    
    # 1. Load input data
    if (!file.exists("inputCaseA")) {
      stop("Required input file 'inputCaseA' is missing from the working directory.")
    }
    
    # Read the input file (try CSV first, fallback to TSV if delimiter is tab)
    inputCaseA = tryCatch({
      df = read.csv("inputCaseA", stringsAsFactors = FALSE)
      if (ncol(df) <= 1) {
        df = read.delim("inputCaseA", stringsAsFactors = FALSE)
      }
      df
    }, error = function(e) {
      stop("Error reading 'inputCaseA': ", e\$message)
    })
    
    # Ensure input is a data frame
    inputCaseA = as.data.frame(inputCaseA)
    
    # 2. Fit GR curves and calculate metrics using GRfit with Case A
    # Dynamically determine grouping variables (all columns except the mandatory ones)
    group_cols = setdiff(colnames(inputCaseA), c("concentration", "cell_count", "cell_count__time0", "cell_count__ctrl"))
    drc_output = GRfit(inputCaseA, groupingVariables = group_cols)
    drc_output
    
    # 3. Extract metrics table using GRgetMetrics
    head(GRgetMetrics(drc_output))
    
    # 4. Extract original and calculated GR values using GRgetValues
    head(GRgetValues(drc_output))
    
    # 5. Extract grouping variables using GRgetGroupVars
    GRgetGroupVars(drc_output)
    
    # 6. Visualize dose-response curves using GRdrawDRC
    # Open a PDF device to capture the static plots
    pdf("gr_dose_response_curves.pdf", width = 10, height = 7)
    
    # Dynamically extract up to 3 experiment names for subset plotting
    exp_names = unique(GRgetMetrics(drc_output)\$experiment)
    subset_exps = exp_names[1:min(3, length(exp_names))]
    
    # Explicitly print() the plots and set plotly = FALSE to allow saving to PDF
    print(GRdrawDRC(drc_output, plotly = FALSE))
    print(GRdrawDRC(drc_output, experiments = subset_exps, plotly = FALSE))
    print(GRdrawDRC(drc_output, experiments = subset_exps, min = 10^(-4), max = 10^2, plotly = FALSE))
    
    dev.off()
    
    # Save meaningful results to output files
    write.table(GRgetMetrics(drc_output), file = "gr_metrics.tsv", quote = FALSE, sep = "\t", row.names = FALSE)
    write.table(GRgetValues(drc_output), file = "gr_values.csv", quote = FALSE, sep = ",", row.names = FALSE)
    saveRDS(drc_output, file = "drc_output.rds")

    writeLines(c(
        '"BIOC_GRMETRICS_GR_METRICS_CASE_A":',
        paste0('    GRmetrics: ', as.character(packageVersion('GRmetrics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gr_metrics_case_a.csv versions.yml
    """
}

workflow BIOC_GRMETRICS_GR_METRICS_CASE_A_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ inputCaseA ] ]

    main:
    BIOC_GRMETRICS_GR_METRICS_CASE_A(ch_input)

    emit:
    tables   = BIOC_GRMETRICS_GR_METRICS_CASE_A.out.tables
    plots    = BIOC_GRMETRICS_GR_METRICS_CASE_A.out.plots
    objects  = BIOC_GRMETRICS_GR_METRICS_CASE_A.out.objects
    versions = BIOC_GRMETRICS_GR_METRICS_CASE_A.out.versions
}
