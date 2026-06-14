#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rmmquant — file_based_quantification
// Quantify gene expression directly from GTF annotation and BAM alignment files.
// Input: test.gtf, test.bam
// Container: quay.io/biocontainers/bioconductor-rmmquant:1.28.0--r45ha27e39d_0
// R packages: BiocStyle, DESeq2, Rmmquant, S4Vectors, SummarizedExperiment, tbx20bamsubset
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rmmquant:1.28.0--r45ha27e39d_0"

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
    .bm_deps <- c("BiocStyle", "DESeq2", "Rmmquant", "S4Vectors", "SummarizedExperiment", "tbx20bamsubset")
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
    
    # Load required libraries
    library(Rmmquant)
    library(SummarizedExperiment)
    library(S4Vectors)
    
    # --- Locate input files from the working directory ---
    gtfFile <- "test.gtf"
    bamFile <- "test.bam"
    
    # Verify that the input files exist before running
    if (!file.exists(gtfFile)) {
      stop(paste("Required GTF file not found in the working directory:", gtfFile))
    }
    if (!file.exists(bamFile)) {
      stop(paste("Required BAM file not found in the working directory:", bamFile))
    }
    
    # --- Run quantification using RmmquantRun ---
    output <- RmmquantRun(gtfFile, bamFile)
    
    # --- Extract count matrix ---
    counts_matrix <- assays(output)\$counts
    
    # --- Extract mapping statistics ---
    mapping_stats <- colData(output)
    
    # --- Write named output files for the results ---
    # Save the count matrix as a CSV file
    write.csv(as.matrix(counts_matrix), "gene_counts.csv", row.names = TRUE)
    
    # Save the mapping statistics as a CSV file
    write.csv(as.data.frame(mapping_stats), "mapping_statistics.csv", row.names = TRUE)
    
    # Save the complete SummarizedExperiment output object as an RDS file
    saveRDS(output, "rmmquant_output.rds")

    writeLines(c(
        '"BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION":',
        paste0('        rmmquant: ', as.character(packageVersion("rmmquant")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_file_based_quantification.csv versions.yml
    """
}

workflow BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test.gtf, test.bam ] ]

    main:
    BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION.out.tables
    plots    = BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION.out.plots
    objects  = BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION.out.objects
    versions = BIOC_RMMQUANT_FILE_BASED_QUANTIFICATION.out.versions
}
