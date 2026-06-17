#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DiscoRhythm — batch_rhythm_analysis
// Execute the entire rhythmicity analysis workflow and generate an HTML report using a single batch function.
// Input: temporal_data.csv
// Container: quay.io/biocontainers/bioconductor-discorhythm:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DiscoRhythm, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the user input file
//  * 2. [Visualization & Output] Execute the complete pipeline and generate an HTML report
//  * 3. [Visualization & Output] Save meaningful results to output files

nextflow.enable.dsl = 2

process BIOC_DISCORHYTHM_BATCH_RHYTHM_ANALYSIS {
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
    .bm_deps <- c("DiscoRhythm")
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
    library(DiscoRhythm)
    
    # --- Read the user input file ---
    # The file must have unique feature IDs in the first column and sample data in subsequent columns.
    # Column names encode metadata as Prefix_Time_UniqueID_ReplicateID.
    # check.names = FALSE is critical to preserve the underscores in the column names.
    input_file <- "temporal_data.csv"
    
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    indata <- read.csv(input_file, header = TRUE, check.names = FALSE)
    
    # --- Execute the complete pipeline and generate an HTML report ---
    # We use the exact function call and arguments from the documented workflow.
    discoODAres <- discoBatch(
      indata = indata,
      report = "discoBatch_example.html",
      ncores = 1,
      main_per = 24,
      timeType = "linear",
      cor_threshold = 3,
      cor_method = "pearson",
      cor_threshType = "sd",
      pca_threshold = 3,
      pca_scale = TRUE,
      pca_pcToCut = paste0("PC", seq_len(4)),
      aov_method = "None",
      aov_pcut = 0.05,
      aov_Fcut = 0,
      avg_method = "Median",
      osc_method = "CS",
      osc_period = 24
    )
    
    # --- Save meaningful results to output files ---
    # Save the full R object
    saveRDS(discoODAres, file = "discoBatch_results.rds")
    
    # Export the rhythmicity analysis tables to CSV
    if (is.data.frame(discoODAres)) {
      write.csv(discoODAres, "rhythmicity_results.csv", row.names = TRUE)
    } else if (is.list(discoODAres)) {
      for (name in names(discoODAres)) {
        if (is.data.frame(discoODAres[[name]])) {
          write.csv(discoODAres[[name]], paste0("rhythmicity_results_", name, ".csv"), row.names = TRUE)
        }
      }
    }
    
    message("DiscoRhythm batch workflow completed successfully.")

    writeLines(c(
        '"BIOC_DISCORHYTHM_BATCH_RHYTHM_ANALYSIS":',
        paste0('    DiscoRhythm: ', as.character(packageVersion('DiscoRhythm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_rhythm_analysis.csv versions.yml
    """
}

workflow BIOC_DISCORHYTHM_BATCH_RHYTHM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ temporal_data.csv ] ]

    main:
    BIOC_DISCORHYTHM_BATCH_RHYTHM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DISCORHYTHM_BATCH_RHYTHM_ANALYSIS.out.tables
    plots    = BIOC_DISCORHYTHM_BATCH_RHYTHM_ANALYSIS.out.plots
    objects  = BIOC_DISCORHYTHM_BATCH_RHYTHM_ANALYSIS.out.objects
    versions = BIOC_DISCORHYTHM_BATCH_RHYTHM_ANALYSIS.out.versions
}
