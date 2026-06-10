#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tximeta — mixed_reference_import
// Import long-read transcript quantifications containing both annotated and novel transcripts, inspect digests, and update metadata with custom ranges.
// Input: experiment_rep1.quant.gz, sample_table.csv
// Container: quay.io/biocontainers/bioconductor-tximeta:1.28.2--r45hdfd78af_0
// Requires: GenomicRanges, SummarizedExperiment, tximeta
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import un-ranged data using importData(). 2. Inspect sequence digests using inspectDigests(). 3. Define novel transcript metadata 

nextflow.enable.dsl = 2

process BIOC_TXIMETA_MIXED_REFERENCE_IMPORT {
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
    .bm_deps <- c("GenomicRanges", "SummarizedExperiment", "tximeta")
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
    
    # Load required libraries
    library(tximeta)
    library(GenomicRanges)
    
    # 1. Read user input files from the working directory
    sample_table_path <- "sample_table.csv"
    quant_file_path <- "experiment_rep1.quant.gz"
    
    if (!file.exists(sample_table_path)) {
      stop(paste("Required input file missing:", sample_table_path))
    }
    if (!file.exists(quant_file_path)) {
      stop(paste("Required input file missing:", quant_file_path))
    }
    
    # Construct coldata from the sample table
    coldata <- read.csv(sample_table_path, stringsAsFactors = FALSE)
    
    # Ensure the required columns 'files' and 'names' are present and correct
    if (!"files" %in% colnames(coldata)) {
      coldata\$files <- quant_file_path
    } else {
      # Ensure the files column points to the correct local file path if needed
      coldata\$files <- quant_file_path
    }
    
    if (!"names" %in% colnames(coldata)) {
      coldata\$names <- "rep1"
    }
    
    # 2. Import un-ranged data using importData()
    se <- importData(coldata, type = "oarfish")
    class(se)
    rowData(se)
    
    # 3. Inspect sequence digests using inspectDigests()
    digests <- inspectDigests(se)
    print(digests)
    
    digests_full <- inspectDigests(se, fullDigest = TRUE)
    print(digests_full)
    
    # Save digests to output files
    write.csv(as.data.frame(digests), "digests.csv", row.names = FALSE)
    write.csv(as.data.frame(digests_full), "digests_full.csv", row.names = FALSE)
    
    # 4. Update metadata (without ranges first)
    se_update <- updateMetadata(se)
    mcols(se_update)
    
    # Save metadata columns to output file
    write.csv(as.data.frame(mcols(se_update)), "mcols_se_update.csv", row.names = FALSE)
    
    # 5. Define novel transcript metadata as a GRanges object
    novel <- data.frame(
      seqnames = paste0("chr", rep(1:22, each = 500)),
      start = 1e6 + 1 + 0:499 * 1000,
      end = 1e6 + 1 + 0:499 * 1000 + 1000 - 1,
      strand = "+",
      tx_name = paste0("novel", 1:(22 * 500)),
      gene_id = paste0("novel_gene", rep(1:(22 * 10), each = 50)),
      type = "protein_coding"
    )
    head(novel)
    
    novel_gr <- as(novel, "GRanges")
    names(novel_gr) <- novel\$tx_name
    
    # 6. Update metadata and attach ranges using updateMetadata()
    se_with_ranges <- updateMetadata(se, txpData = novel_gr, ranges = TRUE)
    rowRanges(se_with_ranges)
    
    # Save final outputs
    saveRDS(se_with_ranges, "se_with_ranges.rds")
    saveRDS(rowRanges(se_with_ranges), "row_ranges.rds")
    
    message("Pipeline completed successfully. Outputs saved to digests.csv, digests_full.csv, mcols_se_update.csv, se_with_ranges.rds, and row_ranges.rds.")

    writeLines(c(
        '"BIOC_TXIMETA_MIXED_REFERENCE_IMPORT":',
        paste0('    tximeta: ', as.character(packageVersion('tximeta')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mixed_reference_import.csv versions.yml
    """
}

workflow BIOC_TXIMETA_MIXED_REFERENCE_IMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ experiment_rep1.quant.gz, sample_table.csv ] ]

    main:
    BIOC_TXIMETA_MIXED_REFERENCE_IMPORT(ch_input)

    emit:
    tables   = BIOC_TXIMETA_MIXED_REFERENCE_IMPORT.out.tables
    plots    = BIOC_TXIMETA_MIXED_REFERENCE_IMPORT.out.plots
    objects  = BIOC_TXIMETA_MIXED_REFERENCE_IMPORT.out.objects
    versions = BIOC_TXIMETA_MIXED_REFERENCE_IMPORT.out.versions
}
