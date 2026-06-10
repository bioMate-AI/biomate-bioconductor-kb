#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CSSQ — differential_binding_from_precalculated_counts
// Identify differentially bound regions step-by-step starting from a pre-calculated tab-separated count matrix.
// Input: sample_count_data.txt, chr19_regions.bed, sample_info.txt
// Container: quay.io/biocontainers/bioconductor-cssq:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CSSQ, GenomicRanges, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load pre-calculated count data into a SummarizedExperiment object using loadCountData
//  * 2. [Core Analysis] Apply Anscombe transformation using ansTransform
//  * 3. [Core Analysis] Normalize transformed counts across samples using normalizeData
//  * 4. [Core Analysis] Perform non-parametric statistical testing for differential binding using DBAnalyze

nextflow.enable.dsl = 2

process BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_PRECALCULATED_COUNTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
        library(CSSQ)
        library(GenomicRanges)
        
        # Define input file paths (expected in the working directory)
        sample_info_file <- "sample_info.txt"
        count_data_file <- "sample_count_data.txt"
        regions_bed_file <- "chr19_regions.bed"
        
        # Verify input files exist before proceeding
        if (!file.exists(sample_info_file)) {
          stop(paste("Required input file missing:", sample_info_file))
        }
        if (!file.exists(count_data_file)) {
          stop(paste("Required input file missing:", count_data_file))
        }
        if (!file.exists(regions_bed_file)) {
          stop(paste("Required input file missing:", regions_bed_file))
        }
        
        # 1. Load sample metadata
        message("Reading sample metadata...")
        sampleInfo <- read.table(sample_info_file, sep = "\t", header = TRUE)
        
        # 2. Load pre-calculated count data into a SummarizedExperiment object
        message("Loading pre-calculated count data...")
        countData <- loadCountData(count_data_file, regions_bed_file, sampleInfo)
        
        # 3. Apply Anscombe transformation
        message("Applying Anscombe transformation...")
        ansCountData <- ansTransform(countData)
        
        # 4. Normalize transformed counts across samples
        message("Normalizing data across samples...")
        normInfo <- normalizeData(ansCountData, numClusters = 4)
        
        # 5. Perform non-parametric statistical testing for differential binding
        message("Performing differential binding analysis...")
        comparison_groups <- unique(as.character(sampleInfo\$Group))[1:2]
        result <- DBAnalyze(normInfo, comparison = comparison_groups)
        
        # 6. Write meaningful output files
        message("Writing output files...")
        
        # Save the primary GRanges result object
        saveRDS(result, "cssq_results.rds")
        
        # Export the differential binding results as a CSV table
        result_df <- as.data.frame(result)
        write.csv(result_df, "cssq_differential_binding_results.csv", row.names = FALSE)
        
        # Export the normalized counts for downstream visualization or analysis
        norm_counts <- SummarizedExperiment::assay(normInfo, "normCount")
        write.csv(as.data.frame(norm_counts), "cssq_normalized_counts.csv", row.names = TRUE)
        
        message("Pipeline completed successfully. Outputs saved to 'cssq_results.rds', 'cssq_differential_binding_results.csv', and 'cssq_normalized_counts.csv'.")

    writeLines(c(
        '"BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_PRECALCULATED_COUNTS":',
        paste0('    CSSQ: ', as.character(packageVersion('CSSQ')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_binding_from_precalculated_counts.csv versions.yml
    """
}

workflow BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_PRECALCULATED_COUNTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_count_data.txt, chr19_regions.bed, sample_info.txt ] ]

    main:
    BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_PRECALCULATED_COUNTS(ch_input)

    emit:
    tables   = BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_PRECALCULATED_COUNTS.out.tables
    plots    = BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_PRECALCULATED_COUNTS.out.plots
    objects  = BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_PRECALCULATED_COUNTS.out.objects
    versions = BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_PRECALCULATED_COUNTS.out.versions
}
