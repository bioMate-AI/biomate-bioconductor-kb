#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OpenStats — fishers_exact_test_workflow
// Perform genotype-to-phenotype association analysis on categorical data using Fisher's Exact Test.
// Input: test_categorical.csv
// Container: quay.io/biocontainers/bioconductor-openstats:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: OpenStats
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Preprocess categorical data and create an OpenStatsList
//  * 2. [Input & Preparation] Run Fisher's Exact Test analysis
//  * 3. [Input & Preparation] Save outputs

nextflow.enable.dsl = 2

process BIOC_OPENSTATS_FISHERS_EXACT_TEST_WORKFLOW {
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
    .bm_deps <- c("OpenStats")
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
    
    library(OpenStats)
    
    # --- Preprocess categorical data and create an OpenStatsList ---
    input_file <- "test_categorical.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    dataset <- read.csv(input_file, na.strings = "-")
    
    test_Cat <- OpenStatsList(
      dataset = dataset,
      testGenotype = "Aff3/Aff3",
      refGenotype = "+/+",
      dataset.colname.genotype = "Genotype",
      dataset.colname.batch = "Assay.Date",
      dataset.colname.lifestage = NULL,
      dataset.colname.weight = "Weight",
      dataset.colname.sex = "Sex",
      debug = FALSE
    )
    
    # --- Run Fisher's Exact Test analysis ---
    FE_result <- OpenStatsAnalysis(
      OpenStatsList = test_Cat,
      method = "FE",
      FE_formula = Thoracic.Processes ~ Genotype + Sex
    )
    
    # --- Save outputs ---
    saveRDS(FE_result, file = "FE_result.rds")
    
    # Generate and save report in JSON format
    report_json <- OpenStatsReport(
      object = FE_result,
      JSON = TRUE,
      RemoveNullKeys = TRUE,
      pretty = TRUE
    )
    writeLines(report_json, "FE_report.json")
    
    # Generate and save plots
    pdf("FE_plots.pdf")
    tryCatch({
      plot(FE_result)
    }, error = function(e) {
      message("Plotting encountered an issue: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_OPENSTATS_FISHERS_EXACT_TEST_WORKFLOW":',
        paste0('    OpenStats: ', as.character(packageVersion('OpenStats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fishers_exact_test_workflow.csv versions.yml
    """
}

workflow BIOC_OPENSTATS_FISHERS_EXACT_TEST_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test_categorical.csv ] ]

    main:
    BIOC_OPENSTATS_FISHERS_EXACT_TEST_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_OPENSTATS_FISHERS_EXACT_TEST_WORKFLOW.out.tables
    plots    = BIOC_OPENSTATS_FISHERS_EXACT_TEST_WORKFLOW.out.plots
    objects  = BIOC_OPENSTATS_FISHERS_EXACT_TEST_WORKFLOW.out.objects
    versions = BIOC_OPENSTATS_FISHERS_EXACT_TEST_WORKFLOW.out.versions
}
