#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: screencounter — dual_barcodes_paired_end
// Quantify dual barcodes present on paired-end reads (one barcode per read).
// Input: read1.fastq, read2.fastq
// Container: quay.io/biocontainers/bioconductor-screencounter:1.10.0--r45ha27e39d_0
// R packages: Biostrings, S4Vectors, SummarizedExperiment, screenCounter
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCREENCOUNTER_DUAL_BARCODES_PAIRED_END {
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
    .bm_deps <- c("Biostrings", "S4Vectors", "SummarizedExperiment", "screenCounter")
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
    library(SummarizedExperiment)
    library(S4Vectors)
    library(Biostrings)
    
    # Define input file paths
    file1 <- "read1.fastq"
    file2 <- "read2.fastq"
    
    # Validate presence of user input files
    if (!file.exists(file1) || !file.exists(file2)) {
      stop(sprintf("Required input files '%s' and/or '%s' not found in the working directory.", file1, file2))
    }
    
    # --- Define valid barcode combinations in a DataFrame ---
    known.pool1 <- c("AGAGAGAGA", "CTCTCTCTC", "GTGTGTGTG", "CACACACAC")
    known.pool2 <- c("ATATATATA", "CGCGCGCGC", "GAGAGAGAG", "CTCTCTCTC")
    
    choices <- expand.grid(known.pool1, known.pool2)
    choices <- DataFrame(barcode1=choices[,1], barcode2=choices[,2])
    
    # Reproduce the vignette's subsetting of valid combinations
    set.seed(42)
    choices <- choices[sample(nrow(choices), nrow(choices)*0.9),]
    
    # --- Quantify dual barcodes using matrixOfDualBarcodes ---
    out <- matrixOfDualBarcodes(
      list(c(file1, file2)), 
      choices=choices,
      template=c("CAGCTACGTACGNNNNNNNNNCCAGCTCGATCG",
                 "TGGGCAGCGACANNNNNNNNNACACGAGGGTAT")
    )
    
    # --- Extract the count matrix using assay ---
    count_matrix <- assay(out)
    
    # --- Extract mapping diagnostics using colData ---
    diagnostics <- colData(out)
    
    # --- Extract barcode identities using rowData ---
    barcode_ids <- rowData(out)
    
    # Write outputs to files
    write.csv(as.matrix(count_matrix), "dual_barcode_counts.csv", row.names=TRUE)
    write.csv(as.data.frame(diagnostics), "mapping_diagnostics.csv", row.names=TRUE)
    write.csv(as.data.frame(barcode_ids), "barcode_identities.csv", row.names=TRUE)
    saveRDS(out, "dual_barcodes_se.rds")

    writeLines(c(
        '"BIOC_SCREENCOUNTER_DUAL_BARCODES_PAIRED_END":',
        paste0('        screencounter: ', as.character(packageVersion("screencounter")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dual_barcodes_paired_end.csv versions.yml
    """
}

workflow BIOC_SCREENCOUNTER_DUAL_BARCODES_PAIRED_END_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ read1.fastq, read2.fastq ] ]

    main:
    BIOC_SCREENCOUNTER_DUAL_BARCODES_PAIRED_END(ch_input)

    emit:
    tables   = BIOC_SCREENCOUNTER_DUAL_BARCODES_PAIRED_END.out.tables
    plots    = BIOC_SCREENCOUNTER_DUAL_BARCODES_PAIRED_END.out.plots
    objects  = BIOC_SCREENCOUNTER_DUAL_BARCODES_PAIRED_END.out.objects
    versions = BIOC_SCREENCOUNTER_DUAL_BARCODES_PAIRED_END.out.versions
}
