#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scTensor — gene_id_conversion
// Convert gene symbols or Ensembl IDs in an expression matrix to NCBI Gene IDs (ENTREZID) to make the matrix compatible with scTensor.
// Input: raw_expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-sctensor:2.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocManager, Homo.sapiens, scTGIF, scTensor
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the appropriate Organism DB package (e.g., Homo.sapiens) or query AnnotationHub. 2. Retrieve the mapping table between curren

nextflow.enable.dsl = 2

process BIOC_SCTENSOR_GENE_ID_CONVERSION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("scTensor", "Homo.sapiens", "scTGIF")
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
    
    # Load required packages
    suppressPackageStartupMessages(library("scTensor"))
    if(!require(Homo.sapiens)){
      BiocManager::install("Homo.sapiens", update=FALSE, ask=FALSE)
      suppressPackageStartupMessages(library(Homo.sapiens))
    }
    if(!require(scTGIF)){
      BiocManager::install("scTGIF", update=FALSE, ask=FALSE)
      suppressPackageStartupMessages(library(scTGIF))
    }
    
    # Read the user input file
    raw_data <- read.csv("raw_expression_matrix.csv", row.names = 1, check.names = FALSE)
    input <- as.matrix(raw_data)
    rowID <- rownames(input)
    
    # Determine if the input IDs are Ensembl IDs or Gene Symbols
    is_ensembl <- any(grepl("^ENSG", rowID))
    
    if (is_ensembl) {
      LefttoRight <- select(Homo.sapiens, column=c("ENSEMBL", "ENTREZID"), keytype="ENSEMBL", keys=rowID)
    } else {
      LefttoRight <- select(Homo.sapiens, column=c("SYMBOL", "ENTREZID"), keytype="SYMBOL", keys=rowID)
    }
    
    # Convert row identifiers using convertRowID from scTGIF package
    input <- convertRowID(input, rowID, LefttoRight)
    
    # Write outputs
    write.csv(input\$output, "converted_expression_matrix.csv", row.names = TRUE)
    write.csv(input\$ctable, "conversion_table.csv", row.names = FALSE)
    saveRDS(input, "converted_data.rds")

    writeLines(c(
        '"BIOC_SCTENSOR_GENE_ID_CONVERSION":',
        paste0('    scTensor: ', as.character(packageVersion('scTensor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_id_conversion.csv versions.yml
    """
}

workflow BIOC_SCTENSOR_GENE_ID_CONVERSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_expression_matrix.csv ] ]

    main:
    BIOC_SCTENSOR_GENE_ID_CONVERSION(ch_input)

    emit:
    tables   = BIOC_SCTENSOR_GENE_ID_CONVERSION.out.tables
    plots    = BIOC_SCTENSOR_GENE_ID_CONVERSION.out.plots
    objects  = BIOC_SCTENSOR_GENE_ID_CONVERSION.out.objects
    versions = BIOC_SCTENSOR_GENE_ID_CONVERSION.out.versions
}
