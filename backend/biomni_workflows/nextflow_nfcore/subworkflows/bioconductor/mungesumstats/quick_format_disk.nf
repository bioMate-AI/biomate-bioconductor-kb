#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MungeSumstats — quick_format_disk
// Quickly standardise column headers and write the data to disk without running the full QC pipeline.
// Input: eduAttainOkbay.txt
// Container: quay.io/biocontainers/bioconductor-mungesumstats:1.18.1--r45hdfd78af_0
// Requires: MungeSumstats
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the summary statistics file and standardise headers using read_sumstats. 2. Write the standardised data to disk as a compress

nextflow.enable.dsl = 2

process BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK {
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
    .bm_deps <- c("MungeSumstats")
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
    
    # Load required library
    library(MungeSumstats)
    
    # Define input path from working directory
    eduAttainOkbayPth <- "eduAttainOkbay.txt"
    
    # Define output path in the working directory
    formatted_path <- "eduAttainOkbay_standardised.tsv.gz"
    
    # 1. Read the summary statistics file and standardise headers using read_sumstats
    dat <- MungeSumstats::read_sumstats(path = eduAttainOkbayPth, standardise_headers = TRUE)
    
    # 2. Write the standardised data to disk as a compressed, tabix-indexed file using write_sumstats
    formatted_path <- MungeSumstats::write_sumstats(sumstats_dt = dat, save_path = formatted_path, tabix_index = TRUE, write_vcf = FALSE, return_path = TRUE)
    
    # Print the final path of the formatted file
    cat("Formatted summary statistics saved to:", formatted_path, "\n")

    writeLines(c(
        '"BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK":',
        paste0('    MungeSumstats: ', as.character(packageVersion('MungeSumstats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_format_disk.csv versions.yml
    """
}

workflow BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eduAttainOkbay.txt ] ]

    main:
    BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK(ch_input)

    emit:
    tables   = BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK.out.tables
    plots    = BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK.out.plots
    objects  = BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK.out.objects
    versions = BIOC_MUNGESUMSTATS_QUICK_FORMAT_DISK.out.versions
}
