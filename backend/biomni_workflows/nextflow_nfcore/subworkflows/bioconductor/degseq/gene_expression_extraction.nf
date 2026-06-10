#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: degseq — gene_expression_extraction
// Count the number of reads mapped to each gene for a single sample from mapped read files and output a gene expression matrix.
// Input: kidneyChr21.bed.txt, refFlatChr21.txt
// Container: quay.io/biocontainers/bioconductor-degseq:1.64.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEGSEQ_GENE_EXPRESSION_EXTRACTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-degseq:1.64.0--r45ha27e39d_0"

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
    .bm_deps <- c("DEGseq")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(DEGseq)
    
    # 1. Define paths to mapped read files and the refFlat annotation file
    # Reading exactly from the working directory as specified
    kidneyR1L1 <- "kidneyChr21.bed.txt"
    refFlat    <- "refFlatChr21.txt"
    
    # Verify input files exist before proceeding
    if (!file.exists(kidneyR1L1)) {
      stop(paste("Required input file missing in working directory:", kidneyR1L1))
    }
    if (!file.exists(refFlat)) {
      stop(paste("Required input file missing in working directory:", refFlat))
    }
    
    mapResultBatch <- c(kidneyR1L1)
    output <- "kidneyChr21.bed.exp"
    
    # 2. Run getGeneExp to count reads mapped to each gene and output the expression values to a file
    exp <- getGeneExp(mapResultBatch, refFlat=refFlat, output=output)
    
    # Write the meaningful results to output files
    write.csv(exp, "gene_expression_matrix.csv", row.names=FALSE)
    saveRDS(exp, "gene_expression_matrix.rds")
    
    # Print a subset of the expression matrix as shown in the vignette
    write.table(exp[30:32,], row.names=FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_DEGSEQ_GENE_EXPRESSION_EXTRACTION":
        degseq: \$(Rscript -e 'cat(as.character(packageVersion("degseq")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_expression_extraction.csv versions.yml
    """
}

workflow BIOC_DEGSEQ_GENE_EXPRESSION_EXTRACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kidneyChr21.bed.txt, refFlatChr21.txt ] ]

    main:
    BIOC_DEGSEQ_GENE_EXPRESSION_EXTRACTION(ch_input)

    emit:
    tables   = BIOC_DEGSEQ_GENE_EXPRESSION_EXTRACTION.out.tables
    plots    = BIOC_DEGSEQ_GENE_EXPRESSION_EXTRACTION.out.plots
    objects  = BIOC_DEGSEQ_GENE_EXPRESSION_EXTRACTION.out.objects
    versions = BIOC_DEGSEQ_GENE_EXPRESSION_EXTRACTION.out.versions
}
