#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: screencounter — combinatorial_barcodes
// Quantify combinatorial barcodes where multiple variable regions are randomly ligated within a template structure.
// Input: combo.fastq
// Container: quay.io/biocontainers/bioconductor-screencounter:1.10.0--r45ha27e39d_0
// R packages: Biostrings, SummarizedExperiment, screenCounter
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCREENCOUNTER_COMBINATORIAL_BARCODES {
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
    .bm_deps <- c("Biostrings", "SummarizedExperiment", "screenCounter")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(screenCounter)
    library(Biostrings)
    library(SummarizedExperiment)
    
    # Define the input file path as specified in the user input requirements
    combo.fq <- "combo.fastq"
    
    # Define the known variable sequence pools
    known1 <- c("AAAA", "CCCC", "GGGG", "TTTT")
    known2 <- c("ATTA", "CGGC", "GCCG", "TAAT")
    
    # --- Quantify combinatorial barcodes using ---
    out <- matrixOfComboBarcodes(combo.fq,
        template="GTACNNNNCATGNNNNGTAC",
        choices=list(first=known1, second=known2))
    
    # Print the SummarizedExperiment object
    print(out)
    
    # --- Extract the count matrix using assay ---
    counts_matrix <- assay(out)
    print(counts_matrix)
    
    # --- Extract barcode identities using rowData ---
    barcode_metadata <- rowData(out)
    print(barcode_metadata)
    
    # Write meaningful results to output files
    # Save the complete SummarizedExperiment object
    saveRDS(out, file = "combinatorial_barcodes_se.rds")
    
    # Save the count matrix as a CSV file
    write.csv(as.matrix(counts_matrix), file = "combinatorial_barcodes_counts.csv", row.names = TRUE)
    
    # Save the barcode metadata (rowData) as a CSV file
    write.csv(as.data.frame(barcode_metadata), file = "combinatorial_barcodes_metadata.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_SCREENCOUNTER_COMBINATORIAL_BARCODES":',
        paste0('        screencounter: ', as.character(packageVersion("screencounter")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_combinatorial_barcodes.csv versions.yml
    """
}

workflow BIOC_SCREENCOUNTER_COMBINATORIAL_BARCODES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ combo.fastq ] ]

    main:
    BIOC_SCREENCOUNTER_COMBINATORIAL_BARCODES(ch_input)

    emit:
    tables   = BIOC_SCREENCOUNTER_COMBINATORIAL_BARCODES.out.tables
    plots    = BIOC_SCREENCOUNTER_COMBINATORIAL_BARCODES.out.plots
    objects  = BIOC_SCREENCOUNTER_COMBINATORIAL_BARCODES.out.objects
    versions = BIOC_SCREENCOUNTER_COMBINATORIAL_BARCODES.out.versions
}
