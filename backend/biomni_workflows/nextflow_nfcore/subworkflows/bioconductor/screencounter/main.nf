#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: screencounter — single_barcodes
// Quantify single barcodes flanked by constant regions from single-end FASTQ files.
// Input: single.fastq
// Container: quay.io/biocontainers/bioconductor-screencounter:1.10.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCREENCOUNTER_SINGLE_BARCODES {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-screencounter:1.10.0--r45ha27e39d_0"

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
    .bm_deps <- c("SummarizedExperiment", "biocparallel", "biocstyle", "biostrings", "screencounter")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(screenCounter)
    library(Biostrings)
    library(SummarizedExperiment)
    
    # Define the input file path as specified by the user
    single.fq <- "single.fastq"
    
    # Verify that the input file exists
    if (!file.exists(single.fq)) {
      stop(paste("Required input file missing:", single.fq))
    }
    
    # Define the pool of known variable sequences (barcodes)
    known <- c("AAAAAAAA", "CCCCCCCC", "GGGGGGGG", "TTTTTTTT")
    
    # Quantify single barcodes using matrixOfSingleBarcodes
    out <- matrixOfSingleBarcodes(
      single.fq, 
      flank5="GTAC", 
      flank3="CATG", 
      choices=known
    )
    
    # Extract the count matrix using assay
    counts_matrix <- assay(out)
    
    # Write meaningful results to output files
    # 1. Save the full SummarizedExperiment object
    saveRDS(out, file="single_barcodes_se.rds")
    
    # 2. Save the quantified counts as a CSV table
    write.csv(as.matrix(counts_matrix), file="single_barcodes_counts.csv", row.names=TRUE)
    
    # Print the results to standard output for verification
    cat("Quantification complete. Summary of the SummarizedExperiment object:\n")
    print(out)
    cat("\nExtracted Count Matrix:\n")
    print(counts_matrix)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SCREENCOUNTER_SINGLE_BARCODES":
        screencounter: \$(Rscript -e 'cat(as.character(packageVersion("screencounter")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_barcodes.csv versions.yml
    """
}

workflow BIOC_SCREENCOUNTER_SINGLE_BARCODES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ single.fastq ] ]

    main:
    BIOC_SCREENCOUNTER_SINGLE_BARCODES(ch_input)

    emit:
    tables   = BIOC_SCREENCOUNTER_SINGLE_BARCODES.out.tables
    plots    = BIOC_SCREENCOUNTER_SINGLE_BARCODES.out.plots
    objects  = BIOC_SCREENCOUNTER_SINGLE_BARCODES.out.objects
    versions = BIOC_SCREENCOUNTER_SINGLE_BARCODES.out.versions
}
