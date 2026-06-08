#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MSstatsConvert — tmt_openms_workflow
// Import, clean, preprocess, and balance multiplexed TMT mass spectrometry data (e.g., OpenMS output) for downstream MSstatsTMT analysis.
// Input: openmstmt_input.csv
// Container: quay.io/biocontainers/bioconductor-msstatsconvert:1.20.0--r45ha27e39d_1
// Requires: MSstatsConvert
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Set up logging settings using MSstatsLogsSettings
//  * 2. [Input & Preparation] Import raw file using MSstatsImport
//  * 3. [Core Analysis] Clean the imported data using MSstatsClean
//  * 4. [Core Analysis] Preprocess and filter the data using MSstatsPreprocess
//  * 5. [Input & Preparation] Create a balanced design using MSstatsBalancedDesign
//  * 6. [Visualization & Output] Save session info using MSstatsSaveSessionInfo

nextflow.enable.dsl = 2

process BIOC_MSSTATSCONVERT_TMT_OPENMS_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required library
    library(MSstatsConvert)
    
    # 1. Set up logging settings
    MSstatsLogsSettings(use_log_file = TRUE, append = FALSE)
    
    # 2. Import raw file
    # Read the user input file from the working directory
    openms_input = read.csv("openmstmt_input.csv")
    
    openms_imported = MSstatsImport(list(input = openms_input),
                                    "MSstatsTMT", "OpenMS")
    
    # 3. Clean the imported data
    openms_cleaned = MSstatsClean(openms_imported)
    
    # Save intermediate cleaned data
    write.csv(openms_cleaned, "openms_cleaned.csv", row.names = FALSE)
    saveRDS(openms_cleaned, "openms_cleaned.rds")
    
    # 4. Preprocess and filter the data
    feature_columns_tmt = c("PeptideSequence", "PrecursorCharge")
    openms_processed = MSstatsPreprocess(
      openms_cleaned, 
      NULL, 
      feature_columns_tmt,
      remove_shared_peptides = TRUE,
      remove_single_feature_proteins = TRUE,
      feature_cleaning = list(remove_features_with_few_measurements = TRUE,
                              summarize_multiple_psms = max)
    )
    
    # Save intermediate processed data
    write.csv(openms_processed, "openms_processed.csv", row.names = FALSE)
    saveRDS(openms_processed, "openms_processed.rds")
    
    # 5. Create a balanced design
    openms_balanced = MSstatsBalancedDesign(openms_processed, feature_columns_tmt)
    
    # Save final balanced design
    write.csv(openms_balanced, "openms_balanced.csv", row.names = FALSE)
    saveRDS(openms_balanced, "openms_balanced.rds")
    
    # 6. Save session info
    MSstatsSaveSessionInfo()

    writeLines(c(
        '"BIOC_MSSTATSCONVERT_TMT_OPENMS_WORKFLOW":',
        paste0('    MSstatsConvert: ', as.character(packageVersion('MSstatsConvert')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tmt_openms_workflow.csv versions.yml
    """
}

workflow BIOC_MSSTATSCONVERT_TMT_OPENMS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ openmstmt_input.csv ] ]

    main:
    BIOC_MSSTATSCONVERT_TMT_OPENMS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MSSTATSCONVERT_TMT_OPENMS_WORKFLOW.out.tables
    plots    = BIOC_MSSTATSCONVERT_TMT_OPENMS_WORKFLOW.out.plots
    objects  = BIOC_MSSTATSCONVERT_TMT_OPENMS_WORKFLOW.out.objects
    versions = BIOC_MSSTATSCONVERT_TMT_OPENMS_WORKFLOW.out.versions
}
