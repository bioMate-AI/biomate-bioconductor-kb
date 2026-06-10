#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: blacksheepr — raw_counts_normalization_and_formatting
// Normalize raw count data and format multi-class annotations into binary comparison columns prior to running outlier analysis.
// Input: raw_counts.tsv, multiclass_annotations.csv
// Container: quay.io/biocontainers/bioconductor-blacksheepr:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: blacksheepr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize raw counts using deva_normalization with Median of Ratios and log2 transformation
//  * 2. [Core Analysis] Convert multi-class annotation columns into binary comparison columns using make_comparison_columns

nextflow.enable.dsl = 2

process BIOC_BLACKSHEEPR_RAW_COUNTS_NORMALIZATION_AND_FORMATTING {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(blacksheepr)
    
    # Define input file paths
    raw_counts_file <- "raw_counts.tsv"
    annotations_file <- "multiclass_annotations.csv"
    
    # Check for existence of input files
    if (!file.exists(raw_counts_file)) {
      stop(paste("Error: Required input file", raw_counts_file, "not found in the working directory."))
    }
    if (!file.exists(annotations_file)) {
      stop(paste("Error: Required input file", annotations_file, "not found in the working directory."))
    }
    
    # 1. Read raw counts
    # To faithfully reproduce the documented code's use of row.names="gene_id" while remaining robust,
    # we check if "gene_id" is present in the header. If not, we fall back to the first column.
    header_cols <- colnames(read.csv(raw_counts_file, sep = "\t", nrows = 1, check.names = FALSE))
    if ("gene_id" %in% header_cols) {
      cts <- as.matrix(read.csv(raw_counts_file, sep = "\t", row.names = "gene_id", check.names = FALSE))
    } else {
      cts <- as.matrix(read.csv(raw_counts_file, sep = "\t", row.names = 1, check.names = FALSE))
    }
    
    # 2. Normalize raw counts using deva_normalization
    message("Normalizing raw counts using Median of Ratios and log2 transformation...")
    norm_cts <- deva_normalization(cts, method = "MoR-log")
    
    # 3. Read multi-class annotations
    # We read the user-provided annotations into the variable 'dummyannotations' to match the documented code
    dummyannotations <- read.csv(annotations_file, row.names = 1, check.names = FALSE)
    
    # 4. Convert multi-class annotation columns into binary comparison columns
    message("Converting multi-class annotations into binary comparison columns...")
    expanded_dummyannotations <- make_comparison_columns(dummyannotations)
    
    # 5. Write output files
    message("Writing output files...")
    # Save normalized counts matrix
    write.table(norm_cts, file = "normalized_counts.tsv", sep = "\t", col.names = NA, quote = FALSE)
    saveRDS(norm_cts, file = "normalized_counts.rds")
    
    # Save expanded binary annotations
    write.csv(expanded_dummyannotations, file = "expanded_annotations.csv", row.names = TRUE, quote = FALSE)
    saveRDS(expanded_dummyannotations, file = "expanded_annotations.rds")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_BLACKSHEEPR_RAW_COUNTS_NORMALIZATION_AND_FORMATTING":',
        paste0('    blacksheepr: ', as.character(packageVersion('blacksheepr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_raw_counts_normalization_and_formatting.csv versions.yml
    """
}

workflow BIOC_BLACKSHEEPR_RAW_COUNTS_NORMALIZATION_AND_FORMATTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_counts.tsv, multiclass_annotations.csv ] ]

    main:
    BIOC_BLACKSHEEPR_RAW_COUNTS_NORMALIZATION_AND_FORMATTING(ch_input)

    emit:
    tables   = BIOC_BLACKSHEEPR_RAW_COUNTS_NORMALIZATION_AND_FORMATTING.out.tables
    plots    = BIOC_BLACKSHEEPR_RAW_COUNTS_NORMALIZATION_AND_FORMATTING.out.plots
    objects  = BIOC_BLACKSHEEPR_RAW_COUNTS_NORMALIZATION_AND_FORMATTING.out.objects
    versions = BIOC_BLACKSHEEPR_RAW_COUNTS_NORMALIZATION_AND_FORMATTING.out.versions
}
