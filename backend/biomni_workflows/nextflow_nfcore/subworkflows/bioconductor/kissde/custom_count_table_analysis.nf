#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kissde — custom_count_table_analysis
// Run differential analysis on a pre-formatted custom table of counts.
// Input: table_counts_alt_splicing.txt
// Container: quay.io/biocontainers/bioconductor-kissde:1.30.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KISSDE_CUSTOM_COUNT_TABLE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-kissde:1.30.0--r45hdfd78af_0"

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
    
    # Load the required library
    library(kissDE)
    
    # 1. Load custom count table from the working directory
    tableCounts <- read.table("table_counts_alt_splicing.txt", head = TRUE)
    
    # 2. Define condition vector
    myConditions <- c(rep("condition_1", 2), rep("condition_2", 2))
    
    # 3. Perform quality control and save the generated plots to a PDF file
    pdf("quality_control_plots.pdf")
    qualityControl(tableCounts, myConditions)
    dev.off()
    
    # 4. Run differential analysis using diffExpressedVariants
    myResults <- diffExpressedVariants(countsData = tableCounts, conditions = myConditions)
    
    # 5. Export results using writeOutputKissDE
    writeOutputKissDE(myResults, output = "kissDE_output.tab")
    
    # Export the PSI/f table for downstream analysis
    writeOutputKissDE(myResults, output = "result_PSI.tab", writePSI = TRUE)
    
    # Save the complete results object as an RDS file
    saveRDS(myResults, file = "kissDE_results.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KISSDE_CUSTOM_COUNT_TABLE_ANALYSIS":
        kissde: \$(Rscript -e 'cat(as.character(packageVersion("kissde")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_count_table_analysis.csv versions.yml
    """
}

workflow BIOC_KISSDE_CUSTOM_COUNT_TABLE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ table_counts_alt_splicing.txt ] ]

    main:
    BIOC_KISSDE_CUSTOM_COUNT_TABLE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_KISSDE_CUSTOM_COUNT_TABLE_ANALYSIS.out.tables
    plots    = BIOC_KISSDE_CUSTOM_COUNT_TABLE_ANALYSIS.out.plots
    objects  = BIOC_KISSDE_CUSTOM_COUNT_TABLE_ANALYSIS.out.objects
    versions = BIOC_KISSDE_CUSTOM_COUNT_TABLE_ANALYSIS.out.versions
}
