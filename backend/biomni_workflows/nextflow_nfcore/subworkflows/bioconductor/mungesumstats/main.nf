#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mungesumstats — standardise_and_qc_gwas
// Standardise column headers and perform comprehensive quality control checks on local tabular or VCF GWAS summary statistics.
// Input: eduAttainOkbay.txt, ALSvcf.vcf
// Container: quay.io/biocontainers/bioconductor-mungesumstats:1.18.1--r45hdfd78af_0
// R packages: MungeSumstats
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUNGESUMSTATS_STANDARDISE_AND_QC_GWAS {
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
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required library
    library(MungeSumstats)
    
    # 1. Define the path to the raw summary statistics files (from the working directory)
    eduAttainOkbayPth <- "eduAttainOkbay.txt"
    ALSvcfPth <- "ALSvcf.vcf"
    
    # 2. Run format_sumstats() specifying the reference genome and output parameters
    reformatted <- MungeSumstats::format_sumstats(
      path = eduAttainOkbayPth, 
      ref_genome = "GRCh37"
    )
    
    reformatted_vcf <- MungeSumstats::format_sumstats(
      path = ALSvcfPth, 
      ref_genome = "GRCh37"
    )
    
    # 3. Run format_sumstats() with logging and imputation indicators enabled
    reformatted_vcf_2 <- MungeSumstats::format_sumstats(
      path = ALSvcfPth, 
      ref_genome = "GRCh37", 
      log_folder_ind = TRUE, 
      imputation_ind = TRUE, 
      log_mungesumstats_msgs = TRUE
    )
    
    # 4. Write named output files for the meaningful results
    # Copy the formatted tabular summary statistics to the working directory
    file.copy(reformatted, "reformatted_eduAttainOkbay.tsv.gz", overwrite = TRUE)
    
    # Copy the formatted VCF summary statistics to the working directory
    file.copy(reformatted_vcf, "reformatted_ALSvcf.tsv.gz", overwrite = TRUE)
    
    # Save the list containing paths to log files and formatted sumstats from the second run
    saveRDS(reformatted_vcf_2, "reformatted_vcf_2_results.rds")
    
    # Copy the sumstats file from the second run to the working directory
    if (is.list(reformatted_vcf_2) && !is.null(reformatted_vcf_2\$sumstats)) {
      file.copy(reformatted_vcf_2\$sumstats, "reformatted_vcf_2.tsv.gz", overwrite = TRUE)
    }

    writeLines(c(
        '"BIOC_MUNGESUMSTATS_STANDARDISE_AND_QC_GWAS":',
        paste0('        mungesumstats: ', as.character(packageVersion("mungesumstats")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standardise_and_qc_gwas.csv versions.yml
    """
}

workflow BIOC_MUNGESUMSTATS_STANDARDISE_AND_QC_GWAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eduAttainOkbay.txt, ALSvcf.vcf ] ]

    main:
    BIOC_MUNGESUMSTATS_STANDARDISE_AND_QC_GWAS(ch_input)

    emit:
    tables   = BIOC_MUNGESUMSTATS_STANDARDISE_AND_QC_GWAS.out.tables
    plots    = BIOC_MUNGESUMSTATS_STANDARDISE_AND_QC_GWAS.out.plots
    objects  = BIOC_MUNGESUMSTATS_STANDARDISE_AND_QC_GWAS.out.objects
    versions = BIOC_MUNGESUMSTATS_STANDARDISE_AND_QC_GWAS.out.versions
}
