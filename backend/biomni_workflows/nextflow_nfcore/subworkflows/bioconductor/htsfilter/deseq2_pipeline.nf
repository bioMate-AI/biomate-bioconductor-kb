#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HTSFilter — deseq2_pipeline
// Filter a DESeqDataSet object within the DESeq2 pipeline and perform differential analysis with independent filtering disabled in DESeq2.
// Input: counts_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-htsfilter:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, HTSFilter
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a DESeqDataSet from the count matrix
//  * 2. [Core Analysis] Run DESeq differential analysis
//  * 3. [Core Analysis] Filter the DESeqDataSet using HTSFilter
//  * 4. [Core Analysis] Extract results with independentFiltering=FALSE

nextflow.enable.dsl = 2

process BIOC_HTSFILTER_DESEQ2_PIPELINE {
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
    .bm_deps <- c("HTSFilter", "DESeq2")
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
    library(HTSFilter)
    library(DESeq2)
    
    # Read user input files
    counts <- read.csv("counts_matrix.csv", row.names = 1, check.names = FALSE)
    metadata <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
    
    # Align counts and metadata
    common_samples <- intersect(colnames(counts), rownames(metadata))
    if (length(common_samples) == 0) {
      if (ncol(counts) == nrow(metadata)) {
        rownames(metadata) <- colnames(counts)
        common_samples <- colnames(counts)
      } else {
        stop("Error: Sample names in counts_matrix.csv and sample_metadata.csv do not match.")
      }
    }
    counts <- counts[, common_samples, drop = FALSE]
    metadata <- metadata[common_samples, , drop = FALSE]
    
    # Identify condition column
    cond_col <- "cell.line"
    if (!(cond_col %in% colnames(metadata))) {
      possible_cols <- c("condition", "group", "cell_line", "treatment")
      found <- possible_cols[possible_cols %in% colnames(metadata)]
      if (length(found) > 0) {
        cond_col <- found[1]
      } else {
        cond_col <- colnames(metadata)[1]
      }
    }
    conds <- as.character(metadata[[cond_col]])
    
    # --- Documented Workflow ---
    conds <- gsub(" ", ".", conds)
    dds <- DESeqDataSetFromMatrix(countData = as.matrix(counts),
                                  colData = data.frame(cell.line = factor(conds)),
                                  design = ~ cell.line)
    dds <- DESeq(dds)
    filter <- HTSFilter(dds, s.len=25, plot=FALSE)\$filteredData
    class(filter)
    dim(filter)
    res <- results(filter, independentFiltering=FALSE)
    head(res)
    # --- End Documented Workflow ---
    
    # Write outputs
    write.csv(as.data.frame(res), "deseq2_results_htsfilter.csv", row.names = TRUE)
    saveRDS(filter, "filtered_dds.rds")
    
    message("Pipeline completed successfully. Outputs written to 'deseq2_results_htsfilter.csv' and 'filtered_dds.rds'.")

    writeLines(c(
        '"BIOC_HTSFILTER_DESEQ2_PIPELINE":',
        paste0('    HTSFilter: ', as.character(packageVersion('HTSFilter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deseq2_pipeline.csv versions.yml
    """
}

workflow BIOC_HTSFILTER_DESEQ2_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_HTSFILTER_DESEQ2_PIPELINE(ch_input)

    emit:
    tables   = BIOC_HTSFILTER_DESEQ2_PIPELINE.out.tables
    plots    = BIOC_HTSFILTER_DESEQ2_PIPELINE.out.plots
    objects  = BIOC_HTSFILTER_DESEQ2_PIPELINE.out.objects
    versions = BIOC_HTSFILTER_DESEQ2_PIPELINE.out.versions
}
