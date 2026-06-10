#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mungesumstats — quick_format_from_disk
// Quickly standardise column headers and convert file formats without running the full QC pipeline.
// Input: eduAttainOkbay.txt
// Container: quay.io/biocontainers/bioconductor-mungesumstats:1.18.1--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mungesumstats:1.18.1--r45hdfd78af_0"

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
    
    # Load required library
    library(MungeSumstats)
    
    # Define input path (reading from the working directory as requested)
    eduAttainOkbayPth <- "eduAttainOkbay.txt"
    
    # Define output path in the working directory
    formatted_path <- "eduAttainOkbay_standardised.tsv.gz"
    
    # 1. Read in the data and standardise header names
    dat <- MungeSumstats::read_sumstats(path = eduAttainOkbayPth, standardise_headers = TRUE)
    
    # 2. Write to disk as a compressed, tab-delimited, tabix-indexed file
    formatted_path <- MungeSumstats::write_sumstats(
      sumstats_dt = dat, 
      save_path = formatted_path, 
      tabix_index = TRUE, 
      write_vcf = FALSE, 
      return_path = TRUE
    )
    
    # Print the path to the formatted file
    cat("Formatted summary statistics saved to:", formatted_path, "\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK":
        mungesumstats: \$(Rscript -e 'cat(as.character(packageVersion("mungesumstats")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_format_from_disk.csv versions.yml
    """
}

workflow BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eduAttainOkbay.txt ] ]

    main:
    BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK(ch_input)

    emit:
    tables   = BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK.out.tables
    plots    = BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK.out.plots
    objects  = BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK.out.objects
    versions = BIOC_MUNGESUMSTATS_QUICK_FORMAT_FROM_DISK.out.versions
}
