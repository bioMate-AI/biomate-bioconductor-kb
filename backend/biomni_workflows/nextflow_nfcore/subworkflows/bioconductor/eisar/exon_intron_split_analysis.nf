#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: eisar — exon_intron_split_analysis
// Perform Exon-Intron Split Analysis (EISA) to identify transcriptional and post-transcriptional regulation from exonic and intronic count tables.
// Input: Fig3abc_GSE33252_rawcounts_exonic.rds, Fig3abc_GSE33252_rawcounts_intronic.rds
// Container: quay.io/biocontainers/bioconductor-eisar:1.22.1--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EISAR_EXON_INTRON_SPLIT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-eisar:1.22.1--r45hdfd78af_0"

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
    .bm_deps <- c("eisaR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(eisaR)
    
    # 1. Load exonic and intronic count tables from the working directory
    cntEx <- readRDS("Fig3abc_GSE33252_rawcounts_exonic.rds")
    cntIn <- readRDS("Fig3abc_GSE33252_rawcounts_intronic.rds")
    
    # Remove "width" column if present
    rEx <- cntEx[, colnames(cntEx) != "width"]
    rIn <- cntIn[, colnames(cntIn) != "width"]
    
    # 2. Define the experimental condition factor
    cond <- factor(c("ES", "ES", "TN", "TN"))
    
    # 3. Run EISA using runEISA() to perform filtering, normalization, model fitting, and contrast calculation
    res <- runEISA(rEx, rIn, cond)
    
    # Save the EISA results object to an RDS file
    saveRDS(res, "eisa_results.rds")
    
    # Save the statistical results table to a CSV file
    if (!is.null(res\$tab.ExIn)) {
        write.csv(res\$tab.ExIn, "eisa_results_table.csv", row.names = TRUE)
    }
    
    # 4. Visualize the results using plotEISA() and save to a PDF file
    pdf("eisa_plot.pdf", width = 7, height = 7)
    plotEISA(res)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_EISAR_EXON_INTRON_SPLIT_ANALYSIS":
        eisar: \$(Rscript -e 'cat(as.character(packageVersion("eisar")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_exon_intron_split_analysis.csv versions.yml
    """
}

workflow BIOC_EISAR_EXON_INTRON_SPLIT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Fig3abc_GSE33252_rawcounts_exonic.rds, Fig3abc_GSE33252_rawcounts_intronic.rds ] ]

    main:
    BIOC_EISAR_EXON_INTRON_SPLIT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EISAR_EXON_INTRON_SPLIT_ANALYSIS.out.tables
    plots    = BIOC_EISAR_EXON_INTRON_SPLIT_ANALYSIS.out.plots
    objects  = BIOC_EISAR_EXON_INTRON_SPLIT_ANALYSIS.out.objects
    versions = BIOC_EISAR_EXON_INTRON_SPLIT_ANALYSIS.out.versions
}
