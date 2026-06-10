#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cfTools — cfdna_data_preparation
// Preprocess aligned paired-end reads and Bismark methylation extractor outputs to generate fragment-level methylation states and calculate marker beta distributi
// Input: demo.sorted.bed.txt.gz, CpG_OT_demo.txt.gz, CpG_OB_demo.txt.gz, beta_matrix.txt.gz, sample_type.txt.gz, marker_index.txt.gz
// Container: quay.io/biocontainers/bioconductor-cftools:1.10.0--r45ha27e39d_0
// R packages: cfTools, GenomicRanges
// Bioconductor: 3.20 | R: 4.4
// Requires: cfTools
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Merge paired-end sequencing reads to fragment-level using MergePEReads
//  * 2. [Core Analysis] Merge CpG methylation states from top and bottom strands using MergeCpGs
//  * 3. [Core Analysis] Combine fragment and methylation information using GenerateFragMeth
//  * 4. [Core Analysis] Calculate paired shape parameters of beta distributions for markers using GenerateMarkerParam

nextflow.enable.dsl = 2

process BIOC_CFTOOLS_CFDNA_DATA_PREPARATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("cfTools", "GenomicRanges")
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
    
    library(cfTools)
    library(utils)
    
    # Define input file paths from the working directory
    PEReads <- "demo.sorted.bed.txt.gz"
    CpG_OT <- "CpG_OT_demo.txt.gz"
    CpG_OB <- "CpG_OB_demo.txt.gz"
    beta_matrix_file <- "beta_matrix.txt.gz"
    sample_type_file <- "sample_type.txt.gz"
    marker_index_file <- "marker_index.txt.gz"
    
    # 1. Merge paired-end sequencing reads to fragment-level
    message("Merging paired-end reads...")
    fragInfo <- MergePEReads(PEReads)
    
    # 2. Merge CpG methylation states from top and bottom strands
    message("Merging CpG methylation states...")
    methInfo <- MergeCpGs(CpG_OT, CpG_OB)
    
    # 3. Combine fragment and methylation information
    message("Generating fragment-level methylation states...")
    fragMeth <- GenerateFragMeth(fragInfo, methInfo)
    
    # 4. Calculate paired shape parameters of beta distributions for markers
    message("Loading marker methylation levels, sample types, and marker names...")
    methLevel <- read.table(beta_matrix_file, row.names = 1, header = TRUE)
    sampleTypes <- read.table(sample_type_file, row.names = 1, header = TRUE)\$sampleType
    markerNames <- read.table(marker_index_file, row.names = 1, header = TRUE)\$markerIndex
    
    message("Generating marker parameters...")
    markerParam <- GenerateMarkerParam(methLevel, sampleTypes, markerNames)
    
    # Address pitfall: Remove parameter values of NA:NA or 0:0 in the output list
    message("Cleaning marker parameters...")
    clean_markerParam <- markerParam
    for (col in colnames(clean_markerParam)) {
      clean_markerParam <- clean_markerParam[!(clean_markerParam[[col]] %in% c("NA:NA", "0:0")), ]
    }
    
    # Save outputs to the working directory
    message("Saving outputs...")
    write.table(fragInfo, "fragInfo.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    write.table(methInfo, "methInfo.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    write.table(fragMeth, "fragMeth.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    write.table(clean_markerParam, "markerParam_cleaned.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CFTOOLS_CFDNA_DATA_PREPARATION":',
        paste0('    cfTools: ', as.character(packageVersion('cfTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cfdna_data_preparation.csv versions.yml
    """
}

workflow BIOC_CFTOOLS_CFDNA_DATA_PREPARATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ demo.sorted.bed.txt.gz, CpG_OT_demo.txt.gz, CpG_OB_demo.txt.gz, beta_matrix.txt.gz, sample_type.txt.gz, marker_index.txt.gz ] ]

    main:
    BIOC_CFTOOLS_CFDNA_DATA_PREPARATION(ch_input)

    emit:
    tables   = BIOC_CFTOOLS_CFDNA_DATA_PREPARATION.out.tables
    plots    = BIOC_CFTOOLS_CFDNA_DATA_PREPARATION.out.plots
    objects  = BIOC_CFTOOLS_CFDNA_DATA_PREPARATION.out.objects
    versions = BIOC_CFTOOLS_CFDNA_DATA_PREPARATION.out.versions
}
