#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epialleleR — short_read_methylation_calling
// Call cytosine methylation and add missing XG/XM tags to short-read BAM files aligned with tools like bwa-meth or BSMAP.
// Input: bwameth-se-unsort-yd.bam, reference.fasta.gz
// Container: quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0
// Requires: epialleleR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess the reference genome
//  * 2. [Visualization & Output] Call methylation and write the results to a new BAM file containing XG/XM tags

nextflow.enable.dsl = 2

process BIOC_EPIALLELER_SHORT_READ_METHYLATION_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("epialleleR")
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
    library(epialleleR)
    
    # Define input file paths from the working directory
    input.bam <- "bwameth-se-unsort-yd.bam"
    ref.fasta <- "reference.fasta.gz"
    output.bam <- "called_methylation_output.bam"
    
    # Stage 1: Preprocess the reference genome
    message("Preprocessing reference genome...")
    genome <- preprocessGenome(ref.fasta)
    
    # Stage 2: Call methylation and write the results to a new BAM file containing XG/XM tags
    message("Calling methylation and writing to output BAM...")
    result <- callMethylation(input.bam, output.bam, genome)
    
    # Save a summary of the methylation calling results to a CSV file
    message("Saving summary report...")
    result.df <- data.frame(
      metric = names(result),
      value = unlist(result),
      row.names = NULL
    )
    write.csv(result.df, file = "methylation_calling_summary.csv", row.names = FALSE)
    
    message("Workflow complete. Output BAM written to: ", output.bam)

    writeLines(c(
        '"BIOC_EPIALLELER_SHORT_READ_METHYLATION_CALLING":',
        paste0('    epialleleR: ', as.character(packageVersion('epialleleR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_short_read_methylation_calling.csv versions.yml
    """
}

workflow BIOC_EPIALLELER_SHORT_READ_METHYLATION_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bwameth-se-unsort-yd.bam, reference.fasta.gz ] ]

    main:
    BIOC_EPIALLELER_SHORT_READ_METHYLATION_CALLING(ch_input)

    emit:
    tables   = BIOC_EPIALLELER_SHORT_READ_METHYLATION_CALLING.out.tables
    plots    = BIOC_EPIALLELER_SHORT_READ_METHYLATION_CALLING.out.plots
    objects  = BIOC_EPIALLELER_SHORT_READ_METHYLATION_CALLING.out.objects
    versions = BIOC_EPIALLELER_SHORT_READ_METHYLATION_CALLING.out.versions
}
