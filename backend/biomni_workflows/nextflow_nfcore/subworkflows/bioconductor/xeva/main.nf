#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Xeva — pdx_growth_and_response_analysis
// Visualize PDX tumor growth curves and compute drug response metrics from a XevaSet object.
// Input: brca, repdx
// Container: quay.io/biocontainers/bioconductor-xeva:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Xeva
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Metadata retrieval
//  * 2. [Visualization & Output] Visualize PDX tumor growth curves
//  * 3. [Visualization & Output] Summarizing response
//  * 4. [Visualization & Output] Generate waterfall plots

nextflow.enable.dsl = 2

process BIOC_XEVA_PDX_GROWTH_AND_RESPONSE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        
    # Load required libraries
    library(Xeva)
    library(Biobase)
    
    # 1. Load the XevaSet datasets from the working directory
    # The user input files are 'brca' and 'repdx' (expected to be RDS files)
    brca <- readRDS("brca")
    repdx <- readRDS("repdx")
    
    # --- Metadata retrieval ---
    brca.mod <- modelInfo(brca)
    
    # Planned Stage 2: Retrieve individual experiment time-volume data
    brca_model_id <- brca.mod\$model.id[1]
    model.data <- getExperiment(brca, model.id = brca_model_id)
    
    # Planned Stage 3: Retrieve batch design information
    brca_batches <- batchInfo(brca)
    brca_batch1 <- brca_batches[1]
    batch.info <- batchInfo(brca, batch = brca_batch1)
    
    # --- Visualize PDX tumor growth curves ---
    repdx_batches <- batchInfo(repdx)
    repdx_batch1 <- repdx_batches[1]
    
    pdf("growth_curves.pdf")
    print(plotPDX(brca, batch = brca_batch1))
    print(plotPDX(repdx, vol.normal = TRUE, batch = repdx_batch1))
    dev.off()
    
    # --- Summarizing response ---
    brca.mr <- summarizeResponse(brca, response.measure = "mRECIST")
    
    # Planned Stage 5: Summarize drug response using angle or linear mixed-effects models
    repdx_response <- response(repdx, batch = repdx_batch1, res.measure = "angle")
    
    # --- Generate waterfall plots ---
    drug_name <- rownames(brca.mr)[1]
    pdf("waterfall_plots.pdf")
    print(waterfall(brca, drug=drug_name, res.measure="best.average.response"))
    dev.off()
    
    # Write the meaningful results to output CSV files
    write.csv(brca.mod, "model_info.csv", row.names = FALSE)
    write.csv(brca.mr, "summarized_response.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_XEVA_PDX_GROWTH_AND_RESPONSE_ANALYSIS":',
        paste0('    Xeva: ', as.character(packageVersion('Xeva')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pdx_growth_and_response_analysis.csv versions.yml
    """
}

workflow BIOC_XEVA_PDX_GROWTH_AND_RESPONSE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ brca, repdx ] ]

    main:
    BIOC_XEVA_PDX_GROWTH_AND_RESPONSE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_XEVA_PDX_GROWTH_AND_RESPONSE_ANALYSIS.out.tables
    plots    = BIOC_XEVA_PDX_GROWTH_AND_RESPONSE_ANALYSIS.out.plots
    objects  = BIOC_XEVA_PDX_GROWTH_AND_RESPONSE_ANALYSIS.out.objects
    versions = BIOC_XEVA_PDX_GROWTH_AND_RESPONSE_ANALYSIS.out.versions
}
