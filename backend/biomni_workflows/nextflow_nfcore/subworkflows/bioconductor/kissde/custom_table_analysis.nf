#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kissDE — custom_table_analysis
// Identify condition-specific variants using a user-provided custom table of counts.
// Input: table_counts_alt_splicing.txt
// Container: quay.io/biocontainers/bioconductor-kissde:1.30.0--r45hdfd78af_0
// Requires: kissDE
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the custom count table using read.table
//  * 2. [Input & Preparation] Define the experimental design condition vector
//  * 3. [Core Analysis] Perform quality control using qualityControl
//  * 4. [Core Analysis] Run differential analysis using diffExpressedVariants
//  * 5. [Visualization & Output] Export results using writeOutputKissDE

nextflow.enable.dsl = 2

process BIOC_KISSDE_CUSTOM_TABLE_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("kissDE")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load the required library
    library(kissDE)
    
    # 1. Load the custom count table from the user-provided file in the working directory
    tableCounts <- read.table("table_counts_alt_splicing.txt", head = TRUE)
    
    # 2. Define the experimental design condition vector
    myConditions <- c(rep("condition_1", 2), rep("condition_2", 2))
    
    # Map the loaded objects to the exact variable names used in the documented function calls
    counts <- tableCounts
    conditions <- myConditions
    
    # 3. Perform quality control and save the resulting plots to a PDF file
    pdf("quality_control_plots.pdf")
    qualityControl(counts, conditions)
    dev.off()
    
    # 4. Run differential analysis to identify condition-specific variants
    results <- diffExpressedVariants(counts, conditions)
    
    # 5. Export results to the specified output file
    writeOutputKissDE(results, output = "kissDE_output.tab")

    writeLines(c(
        '"BIOC_KISSDE_CUSTOM_TABLE_ANALYSIS":',
        paste0('    kissDE: ', as.character(packageVersion('kissDE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_table_analysis.csv versions.yml
    """
}

workflow BIOC_KISSDE_CUSTOM_TABLE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ table_counts_alt_splicing.txt ] ]

    main:
    BIOC_KISSDE_CUSTOM_TABLE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_KISSDE_CUSTOM_TABLE_ANALYSIS.out.tables
    plots    = BIOC_KISSDE_CUSTOM_TABLE_ANALYSIS.out.plots
    objects  = BIOC_KISSDE_CUSTOM_TABLE_ANALYSIS.out.objects
    versions = BIOC_KISSDE_CUSTOM_TABLE_ANALYSIS.out.versions
}
