#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Linnorm — normalization_and_transformation
// Normalize, transform, and optionally impute raw count or expression data for downstream parametric analysis or export.
// Input: Islam2011
// Container: quay.io/biocontainers/bioconductor-linnorm:2.34.0--r45ha27e39d_0
// R packages: gplots, igraph, knitr, Linnorm, RColorBrewer
// Bioconductor: 3.20 | R: 4.4
// Requires: Linnorm
// QC: low-count filtering, missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the Linnorm library and dataset
//  * 2. [Core Analysis] Perform normalizing transformation with or without low-count filtering
//  * 3. [Visualization & Output] Export transformed data to a tab-delimited file
//  * 4. [Core Analysis] Perform normalization to XPM or Raw counts
//  * 5. [Core Analysis] Optionally perform data imputation or select stable genes

nextflow.enable.dsl = 2

process BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("gplots", "igraph", "knitr", "Linnorm", "RColorBrewer")
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
    library(Linnorm)
    
    # Read the user input file "Islam2011" from the working directory.
    # We assume it is a tab-separated or comma-separated file with gene names as row names.
    if (file.exists("Islam2011")) {
      Islam2011 <- tryCatch({
        as.matrix(read.table("Islam2011", header=TRUE, sep="\t", row.names=1, check.names=FALSE))
      }, error = function(e) {
        as.matrix(read.csv("Islam2011", header=TRUE, row.names=1, check.names=FALSE))
      })
    } else {
      stop("Required input file 'Islam2011' not found in the working directory.")
    }
    
    # Do not filter gene list:
    Transformed <- Linnorm(Islam2011)
    
    # Filter low count genes
    result <- Linnorm(Islam2011, Filter=TRUE)
    FTransformed <- result[["Linnorm"]]
    
    # You can use this file with Excel.
    # This file includes all genes.
    write.table(Transformed, "Transformed.txt",
    quote=FALSE, sep="\t", col.names=TRUE, row.names=TRUE)
    
    # This file filtered low count genes.
    write.table(FTransformed, "Transformed.txt",
    quote=FALSE, sep="\t", col.names=TRUE, row.names=TRUE)
    
    # Also write FTransformed to a unique filename to avoid overwriting Transformed.txt
    write.table(FTransformed, "FTransformed.txt",
    quote=FALSE, sep="\t", col.names=TRUE, row.names=TRUE)
    
    # Normalization
    Normalized <- Linnorm.Norm(Islam2011)
    
    # You can use this file with Excel.
    write.table(Normalized, "Normalized.txt",
    quote=FALSE, sep="\t", col.names=TRUE, row.names=TRUE)
    
    # Data Imputation
    DataImputed <- Linnorm.DataImput(Transformed)
    
    # Or, users can directly perform data imputation during transformation.
    DataImputed <- Linnorm(Islam2011,DataImputation=TRUE)
    
    # Save imputed data
    write.table(DataImputed, "DataImputed.txt",
    quote=FALSE, sep="\t", col.names=TRUE, row.names=TRUE)
    
    # Obtain stable genes
    StableGenes <- Linnorm.SGenes(Islam2011)
    
    # Save stable genes
    write.table(StableGenes, "StableGenes.txt",
    quote=FALSE, sep="\t", col.names=TRUE, row.names=TRUE)
    
    # Save RDS objects for downstream R analysis
    saveRDS(Transformed, "Transformed.rds")
    saveRDS(FTransformed, "FTransformed.rds")
    saveRDS(Normalized, "Normalized.rds")
    saveRDS(DataImputed, "DataImputed.rds")
    saveRDS(StableGenes, "StableGenes.rds")

    writeLines(c(
        '"BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION":',
        paste0('    Linnorm: ', as.character(packageVersion('Linnorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_normalization_and_transformation.csv versions.yml
    """
}

workflow BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Islam2011 ] ]

    main:
    BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION(ch_input)

    emit:
    tables   = BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION.out.tables
    plots    = BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION.out.plots
    objects  = BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION.out.objects
    versions = BIOC_LINNORM_NORMALIZATION_AND_TRANSFORMATION.out.versions
}
