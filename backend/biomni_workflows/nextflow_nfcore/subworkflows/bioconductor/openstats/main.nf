#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OpenStats — linear_mixed_model_workflow
// Perform genotype-to-phenotype association analysis on continuous data using a Linear Mixed Model (LMM) framework, including split-effect estimation, reporting, 
// Input: test_continuous.csv
// Container: quay.io/biocontainers/bioconductor-openstats:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: OpenStats
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Preprocess continuous data and create an OpenStatsList object using OpenStatsList. 2. Run the Linear Mixed Model analysis using Op

nextflow.enable.dsl = 2

process BIOC_OPENSTATS_LINEAR_MIXED_MODEL_WORKFLOW {
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
    
    # Load the required package
    library(OpenStats)
    
    # 1. Preprocess continuous data and create an OpenStatsList object
    # Read the user input file from the working directory
    input_file <- "test_continuous.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    
    dataset_df <- read.csv(input_file)
    
    test_Cont <- OpenStatsList(
      dataset = dataset_df,
      testGenotype = "experimental",
      refGenotype = "control",
      dataset.colname.genotype = "biological_sample_group",
      dataset.colname.batch = "date_of_experiment",
      dataset.colname.lifestage = NULL,
      dataset.colname.weight = "weight",
      dataset.colname.sex = "sex",
      debug = FALSE
    )
    
    # Save the preprocessed OpenStatsList object
    saveRDS(test_Cont, "test_Cont_List.rds")
    
    # 2. Run the Linear Mixed Model analysis using OpenStatsAnalysis
    MM_result <- OpenStatsAnalysis(
      OpenStatsList = test_Cont,
      method = "MM",
      MM_fixed = data_point ~ Genotype + Weight,
      debug = FALSE
    )
    
    # Save the analysis result object
    saveRDS(MM_result, "MM_result.rds")
    
    # 3. Estimate split effects with respect to variables (e.g., Sex)
    Spliteffect <- OpenStatsComplementarySplit(
      object = MM_result,
      variables = "Sex"
    )
    
    # Save the split effects object
    saveRDS(Spliteffect, "Spliteffect.rds")
    
    # 4. Generate a summary table of the analysis and save to a text file
    sink("MM_result_summary.txt")
    summary(MM_result)
    sink()
    
    # Also generate and save summary for the split effects
    sink("Spliteffect_summary.txt")
    summary(Spliteffect)
    sink()
    
    # 5. Export detailed reports in JSON format and save to a file
    json_report <- OpenStatsReport(
      object = MM_result,
      JSON = TRUE,
      RemoveNullKeys = TRUE,
      pretty = TRUE
    )
    writeLines(json_report, "MM_result_report.json")
    
    # 6. Plot model diagnostics and save to a PDF file
    pdf("MM_result_plots.pdf", width = 8, height = 8)
    plot(MM_result, col = 2)
    dev.off()

    writeLines(c(
        '"BIOC_OPENSTATS_LINEAR_MIXED_MODEL_WORKFLOW":',
        paste0('    OpenStats: ', as.character(packageVersion('OpenStats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_linear_mixed_model_workflow.csv versions.yml
    """
}

workflow BIOC_OPENSTATS_LINEAR_MIXED_MODEL_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test_continuous.csv ] ]

    main:
    BIOC_OPENSTATS_LINEAR_MIXED_MODEL_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_OPENSTATS_LINEAR_MIXED_MODEL_WORKFLOW.out.tables
    plots    = BIOC_OPENSTATS_LINEAR_MIXED_MODEL_WORKFLOW.out.plots
    objects  = BIOC_OPENSTATS_LINEAR_MIXED_MODEL_WORKFLOW.out.objects
    versions = BIOC_OPENSTATS_LINEAR_MIXED_MODEL_WORKFLOW.out.versions
}
