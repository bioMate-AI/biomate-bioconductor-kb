#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PhenStat — mixed_model_quantitative_analysis
// Perform linear mixed model analysis on quantitative phenotypic data to test for genotype effects while controlling for batch and sex.
// Input: phenotypic_data.csv
// Container: quay.io/biocontainers/bioconductor-phenstat:2.42.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PhenStat
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and create a PhenList object using PhenList()
//  * 2. [Core Analysis] Run the statistical analysis using testDataset() with method="MM"
//  * 3. [Core Analysis] Extract classification tags using classificationTag()
//  * 4. [Visualization & Output] Generate diagnostic plots using plot()

nextflow.enable.dsl = 2

process BIOC_PHENSTAT_MIXED_MODEL_QUANTITATIVE_ANALYSIS {
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
        
        # Load the required library
        library(PhenStat)
        
        # 1. Load data and create a PhenList object
        # The pipeline expects 'phenotypic_data.csv' in the working directory
        dataset <- read.csv("phenotypic_data.csv")
        
        phenList <- PhenList(
          dataset, 
          testGenotype="KO", 
          refGenotype="WT", 
          dataset.colname.batch="Batch", 
          dataset.colname.genotype="Genotype", 
          dataset.colname.sex="Sex"
        )
        
        # 2. Run the statistical analysis using Mixed Models (MM)
        result <- testDataset(
          phenList, 
          depVariable="Value", 
          method="MM", 
          equation="withoutWeight"
        )
        
        # 3. Extract classification tags
        class_tag <- classificationTag(result)
        
        # 4. Generate diagnostic plots and save to PDF
        pdf("diagnostic_plots.pdf", width=8, height=8)
        plot(result)
        dev.off()
        
        # 5. Save outputs to files
        # Save the main result object as an RDS file
        saveRDS(result, file="phenstat_result.rds")
        
        # Save a text summary of the analysis and classification
        sink("analysis_summary.txt")
        cat("====================================================\n")
        cat("PhenStat Mixed Model Quantitative Analysis Summary\n")
        cat("====================================================\n\n")
        cat("Classification Tag:\n")
        print(class_tag)
        cat("\nModel Summary:\n")
        summary(result)
        sink()
        
        # Save detailed statistical vector output to a CSV file
        results_vector <- vectorOutput(result)
        write.csv(as.data.frame(t(results_vector)), "statistical_results.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_PHENSTAT_MIXED_MODEL_QUANTITATIVE_ANALYSIS":',
        paste0('    PhenStat: ', as.character(packageVersion('PhenStat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mixed_model_quantitative_analysis.csv versions.yml
    """
}

workflow BIOC_PHENSTAT_MIXED_MODEL_QUANTITATIVE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ phenotypic_data.csv ] ]

    main:
    BIOC_PHENSTAT_MIXED_MODEL_QUANTITATIVE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PHENSTAT_MIXED_MODEL_QUANTITATIVE_ANALYSIS.out.tables
    plots    = BIOC_PHENSTAT_MIXED_MODEL_QUANTITATIVE_ANALYSIS.out.plots
    objects  = BIOC_PHENSTAT_MIXED_MODEL_QUANTITATIVE_ANALYSIS.out.objects
    versions = BIOC_PHENSTAT_MIXED_MODEL_QUANTITATIVE_ANALYSIS.out.versions
}
