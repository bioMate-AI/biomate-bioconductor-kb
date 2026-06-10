#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: screencounter — random_barcodes
// Quantify random barcodes synthesized from a nucleotide mixture without a known pool of sequences.
// Input: random.fastq
// Container: quay.io/biocontainers/bioconductor-screencounter:1.10.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCREENCOUNTER_RANDOM_BARCODES {
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
    .bm_deps <- c("SummarizedExperiment", "screenCounter")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(screenCounter)
    library(SummarizedExperiment)
    
    # Define the input file as specified by the user
    single.fq <- "random.fastq"
    
    # Check if the input file exists before proceeding
    if (!file.exists(single.fq)) {
      stop(paste("Required input file missing:", single.fq))
    }
    
    # Quantify random barcodes using the documented function and arguments
    out <- matrixOfRandomBarcodes(single.fq,
        template="CCCAGTNNNNNNNNGGGATAC")
    
    # Display the SummarizedExperiment object
    print(out)
    
    # Extract the count matrix using assay
    counts_matrix <- assay(out)
    
    # Display the head of the assay
    print(head(counts_matrix))
    
    # Write meaningful outputs to the working directory
    # 1. Save the complete SummarizedExperiment object as an RDS file
    saveRDS(out, file = "random_barcodes_results.rds")
    
    # 2. Save the quantified barcode counts as a CSV table
    write.csv(as.matrix(counts_matrix), file = "random_barcodes_counts.csv", row.names = TRUE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SCREENCOUNTER_RANDOM_BARCODES":
        screencounter: \$(Rscript -e 'cat(as.character(packageVersion("screencounter")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_random_barcodes.csv versions.yml
    """
}

workflow BIOC_SCREENCOUNTER_RANDOM_BARCODES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ random.fastq ] ]

    main:
    BIOC_SCREENCOUNTER_RANDOM_BARCODES(ch_input)

    emit:
    tables   = BIOC_SCREENCOUNTER_RANDOM_BARCODES.out.tables
    plots    = BIOC_SCREENCOUNTER_RANDOM_BARCODES.out.plots
    objects  = BIOC_SCREENCOUNTER_RANDOM_BARCODES.out.objects
    versions = BIOC_SCREENCOUNTER_RANDOM_BARCODES.out.versions
}
