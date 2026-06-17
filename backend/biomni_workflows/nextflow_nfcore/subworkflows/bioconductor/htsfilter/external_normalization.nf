#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HTSFilter — external_normalization
// Filter count data that has been normalized using an external method (e.g., EDASeq full quantile normalization) by setting norm="none".
// Input: counts_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-htsfilter:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, EDASeq, HTSFilter
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a SeqExpressionSet and normalize using EDASeq betweenLaneNormalization
//  * 2. [Core Analysis] Apply HTSFilter with norm="none"
//  * 3. [Core Analysis] Identify filtered and unfiltered genes using the "on" vector

nextflow.enable.dsl = 2

process BIOC_HTSFILTER_EXTERNAL_NORMALIZATION {
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
    .bm_deps <- c("Biobase", "EDASeq", "HTSFilter")
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
    library(Biobase)
    library(EDASeq)
    library(HTSFilter)
    
    # 1. Read user input files
    counts_data <- read.csv("counts_matrix.csv", row.names = 1, check.names = FALSE)
    counts_matrix <- as.matrix(counts_data)
    
    sample_metadata <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
    
    # Align counts matrix and metadata by sample names
    common_samples <- intersect(colnames(counts_matrix), rownames(sample_metadata))
    if (length(common_samples) == 0) {
      stop("Error: No matching sample names found between counts_matrix.csv and sample_metadata.csv")
    }
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    sample_metadata <- sample_metadata[common_samples, , drop = FALSE]
    
    # Identify the condition column for filtering
    col_name <- "cell.line"
    if (!col_name %in% colnames(sample_metadata)) {
      possible_cols <- c("condition", "group", colnames(sample_metadata)[1])
      col_name <- possible_cols[possible_cols %in% colnames(sample_metadata)][1]
    }
    conds <- as.character(sample_metadata[[col_name]])
    
    # Create AnnotatedDataFrame for phenoData
    pheno_data <- AnnotatedDataFrame(sample_metadata)
    
    # 2. Create a SeqExpressionSet and normalize using EDASeq betweenLaneNormalization
    ses <- newSeqExpressionSet(counts_matrix,
           phenoData=pheno_data)
    ses.norm <- betweenLaneNormalization(ses, which="full")
    
    # 3. Apply HTSFilter with norm="none"
    filter <- HTSFilter(normCounts(ses.norm), conds, s.len=25, norm="none",
              plot=FALSE)
    
    # 4. Identify filtered and unfiltered genes using the "on" vector
    head(filter\$on)
    table(filter\$on)
    
    # 5. Write meaningful output files
    # Save the complete HTSFilter list object
    saveRDS(filter, file = "htsfilter_results.rds")
    
    # Save the filtering status (1 = kept, 0 = filtered) for each gene
    filter_status <- data.frame(
      Gene = names(filter\$on),
      Keep = filter\$on,
      stringsAsFactors = FALSE
    )
    write.csv(filter_status, file = "gene_filter_status.csv", row.names = FALSE)
    
    # Save the normalized counts for the retained (unfiltered) genes
    normalized_counts <- normCounts(ses.norm)
    filtered_counts <- normalized_counts[filter\$on == 1, , drop = FALSE]
    write.csv(filtered_counts, file = "normalized_filtered_counts.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_HTSFILTER_EXTERNAL_NORMALIZATION":',
        paste0('    HTSFilter: ', as.character(packageVersion('HTSFilter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_external_normalization.csv versions.yml
    """
}

workflow BIOC_HTSFILTER_EXTERNAL_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_HTSFILTER_EXTERNAL_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_HTSFILTER_EXTERNAL_NORMALIZATION.out.tables
    plots    = BIOC_HTSFILTER_EXTERNAL_NORMALIZATION.out.plots
    objects  = BIOC_HTSFILTER_EXTERNAL_NORMALIZATION.out.objects
    versions = BIOC_HTSFILTER_EXTERNAL_NORMALIZATION.out.versions
}
