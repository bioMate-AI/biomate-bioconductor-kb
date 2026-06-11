#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OpenStats — reference_range_plus_workflow
// Perform genotype-to-phenotype association analysis on continuous data using the Reference Range Plus framework when LMM is not suitable or control sample size i
// Input: test_continuous.csv
// Container: quay.io/biocontainers/bioconductor-openstats:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: OpenStats
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Preprocess continuous data and create an OpenStatsList
//  * 2. [Input & Preparation] Run the Reference Range Plus analysis
//  * 3. [Input & Preparation] Save outputs

nextflow.enable.dsl = 2

process BIOC_OPENSTATS_REFERENCE_RANGE_PLUS_WORKFLOW {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("OpenStats")
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
    library(OpenStats)
    
    # Define input file path
    input_file <- "test_continuous.csv"
    
    # Check if the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # --- Preprocess continuous data and create an OpenStatsList ---
    test_Cont <- OpenStatsList(
      dataset = read.csv(input_file),
      testGenotype = "experimental",
      refGenotype = "control",
      dataset.colname.genotype = "biological_sample_group",
      dataset.colname.batch = "date_of_experiment",
      dataset.colname.lifestage = NULL,
      dataset.colname.weight = "weight",
      dataset.colname.sex = "sex",
      debug = FALSE
    )
    
    # --- Run the Reference Range Plus analysis ---
    RR_result <- OpenStatsAnalysis(
      OpenStatsList = test_Cont,
      method = "RR",
      RR_formula = data_point ~ Genotype + Sex
    )
    
    # --- Save outputs ---
    # Save the complete analysis object
    saveRDS(RR_result, file = "RR_result.rds")
    
    # Save a detailed JSON report
    json_report <- OpenStatsReport(
      object = RR_result,
      JSON = TRUE,
      RemoveNullKeys = TRUE,
      pretty = TRUE
    )
    writeLines(json_report, con = "RR_report.json")
    
    # Save a text summary of the analysis
    sink("RR_summary.txt")
    cat("=== OpenStats Reference Range Plus Analysis Summary ===\n\n")
    print(summary(RR_result))
    sink()
    
    # Save diagnostic plots to PDF
    pdf("RR_plots.pdf", width = 8, height = 6)
    tryCatch({
      plot(RR_result)
    }, error = function(e) {
      message("Warning: Plotting encountered an issue: ", e\$message)
    })
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved: RR_result.rds, RR_report.json, RR_summary.txt, RR_plots.pdf")

    writeLines(c(
        '"BIOC_OPENSTATS_REFERENCE_RANGE_PLUS_WORKFLOW":',
        paste0('    OpenStats: ', as.character(packageVersion('OpenStats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_range_plus_workflow.csv versions.yml
    """
}

workflow BIOC_OPENSTATS_REFERENCE_RANGE_PLUS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test_continuous.csv ] ]

    main:
    BIOC_OPENSTATS_REFERENCE_RANGE_PLUS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_OPENSTATS_REFERENCE_RANGE_PLUS_WORKFLOW.out.tables
    plots    = BIOC_OPENSTATS_REFERENCE_RANGE_PLUS_WORKFLOW.out.plots
    objects  = BIOC_OPENSTATS_REFERENCE_RANGE_PLUS_WORKFLOW.out.objects
    versions = BIOC_OPENSTATS_REFERENCE_RANGE_PLUS_WORKFLOW.out.versions
}
