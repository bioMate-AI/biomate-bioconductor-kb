#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: StructuralVariantAnnotation — transitive_breakpoint_identification
// Identify transitive structural variant calls that can be explained by multiple other constituent breakpoints.
// Input: truthset_somaticSVs_COLO829.vcf, colo829_nanoSV_truth_overlap.vcf
// Container: quay.io/biocontainers/bioconductor-structuralvariantannotation:1.26.0--r45hdfd78af_0
// Requires: StructuralVariantAnnotation, VariantAnnotation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load truth and query VCF files using readVcf
//  * 2. [Core Analysis] Convert VCFs to GRanges using breakpointRanges, optionally inferring missing breakends
//  * 3. [Core Analysis] Identify transitive calls using findTransitiveCalls

nextflow.enable.dsl = 2

process BIOC_STRUCTURALVARIANTANNOTATION_TRANSITIVE_BREAKPOINT_IDENTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(VariantAnnotation)
    library(StructuralVariantAnnotation)
    
    # Define input file paths (expected in the working directory)
    truth_vcf_file <- "truthset_somaticSVs_COLO829.vcf"
    nanosv_vcf_file <- "colo829_nanoSV_truth_overlap.vcf"
    
    # Verify input files exist
    if (!file.exists(truth_vcf_file)) {
      stop(paste("Required input file missing:", truth_vcf_file))
    }
    if (!file.exists(nanosv_vcf_file)) {
      stop(paste("Required input file missing:", nanosv_vcf_file))
    }
    
    # 1. Load truth and query VCF files using readVcf and convert to GRanges using breakpointRanges
    message("Parsing truth set VCF and converting to breakpoint GRanges...")
    colo829_truth_bpgr  <- breakpointRanges(readVcf(truth_vcf_file))
    
    message("Parsing NanoSV VCF and converting to breakpoint GRanges...")
    colo829_nanosv_bpgr <- breakpointRanges(readVcf(nanosv_vcf_file), 
                                            inferMissingBreakends=TRUE, 
                                            ignoreUnknownSymbolicAlleles=TRUE)
    
    # 2. Identify transitive calls using findTransitiveCalls
    message("Identifying transitive structural variant calls...")
    transitive_calls <- findTransitiveCalls(colo829_nanosv_bpgr, colo829_truth_bpgr)
    
    # 3. Save results to output files
    message("Saving results...")
    
    # Save the raw S4 DataFrame object
    saveRDS(transitive_calls, "transitive_calls.rds")
    
    # Save the parsed GRanges objects for downstream utility
    saveRDS(colo829_truth_bpgr, "colo829_truth_bpgr.rds")
    saveRDS(colo829_nanosv_bpgr, "colo829_nanosv_bpgr.rds")
    
    # Convert the DataFrame to a standard data.frame and format list columns for CSV export
    if (nrow(transitive_calls) > 0) {
      df_out <- as.data.frame(transitive_calls)
      
      # Flatten list columns to semicolon-separated strings for CSV compatibility
      if ("traversed_breakpoint_names" %in% colnames(df_out)) {
        df_out\$traversed_breakpoint_names <- sapply(df_out\$traversed_breakpoint_names, paste, collapse = ";")
      }
      if ("distance_to_traversed_breakpoint" %in% colnames(df_out)) {
        df_out\$distance_to_traversed_breakpoint <- sapply(df_out\$distance_to_traversed_breakpoint, paste, collapse = ";")
      }
      
      write.csv(df_out, "transitive_calls.csv", row.names = FALSE)
      message(paste("Successfully identified", nrow(df_out), "transitive calls and wrote to 'transitive_calls.csv'."))
    } else {
      # Write an empty CSV with headers if no transitive calls were found
      headers <- data.frame(transitive_breakpoint_name=character(),
                            total_distance=integer(),
                            traversed_breakpoint_names=character(),
                            distance_to_traversed_breakpoint=character())
      write.csv(headers, "transitive_calls.csv", row.names = FALSE)
      message("No transitive calls identified. Empty table written to 'transitive_calls.csv'.")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_STRUCTURALVARIANTANNOTATION_TRANSITIVE_BREAKPOINT_IDENTIFICATION":',
        paste0('    StructuralVariantAnnotation: ', as.character(packageVersion('StructuralVariantAnnotation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transitive_breakpoint_identification.csv versions.yml
    """
}

workflow BIOC_STRUCTURALVARIANTANNOTATION_TRANSITIVE_BREAKPOINT_IDENTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ truthset_somaticSVs_COLO829.vcf, colo829_nanoSV_truth_overlap.vcf ] ]

    main:
    BIOC_STRUCTURALVARIANTANNOTATION_TRANSITIVE_BREAKPOINT_IDENTIFICATION(ch_input)

    emit:
    tables   = BIOC_STRUCTURALVARIANTANNOTATION_TRANSITIVE_BREAKPOINT_IDENTIFICATION.out.tables
    plots    = BIOC_STRUCTURALVARIANTANNOTATION_TRANSITIVE_BREAKPOINT_IDENTIFICATION.out.plots
    objects  = BIOC_STRUCTURALVARIANTANNOTATION_TRANSITIVE_BREAKPOINT_IDENTIFICATION.out.objects
    versions = BIOC_STRUCTURALVARIANTANNOTATION_TRANSITIVE_BREAKPOINT_IDENTIFICATION.out.versions
}
