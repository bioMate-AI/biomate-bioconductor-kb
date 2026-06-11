#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metagene2 — large_dataset_analysis
// Manage large datasets by processing regions separately and merging results before plotting to avoid memory limits.
// Input: bam_files, regions
// Container: quay.io/biocontainers/bioconductor-metagene2:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, ggplot2, metagene2, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Initialize separate metagene2 objects; 2. Extract and add metadata; 3. Combine data frames with rbind; 4. Plot combined data

nextflow.enable.dsl = 2

process BIOC_METAGENE2_LARGE_DATASET_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    library(metagene2)
    library(GenomicRanges)
    library(ggplot2)
    
    # -----------------------------------------------------------------
    # 1. Read User Input Files from the Working Directory
    # -----------------------------------------------------------------
    
    # Identify indexed BAM files in the working directory
    bam_files <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    if (length(bam_files) == 0) {
      stop("Error: No BAM files found in the working directory.")
    }
    
    # Verify that corresponding index files (.bai) exist
    for (bam in bam_files) {
      bai1 <- paste0(bam, ".bai")
      bai2 <- sub("\\\\.bam\$", ".bai", bam)
      if (!file.exists(bai1) && !file.exists(bai2)) {
        stop(paste("Error: Missing index file for BAM:", bam))
      }
    }
    
    # Load genomic regions (expected as a GRangesList or list of GRanges in an RDS file,
    # or constructed from BED files in the working directory)
    if (file.exists("regions.rds")) {
      regions <- readRDS("regions.rds")
    } else {
      # Fallback: Attempt to read BED files if regions.rds is not present
      bed_files <- list.files(pattern = "\\\\.bed\$", full.names = TRUE)
      if (length(bed_files) >= 2) {
        if (!requireNamespace("rtracklayer", quietly = TRUE)) {
          stop("Error: rtracklayer package is required to read BED files.")
        }
        regions_list <- lapply(bed_files, rtracklayer::import)
        names(regions_list) <- tools::file_path_sans_ext(basename(bed_files))
        regions <- GRangesList(regions_list)
      } else {
        stop("Error: Please provide 'regions.rds' or at least two '.bed' files in the working directory.")
      }
    }
    
    # Ensure we have at least two sets of regions to process separately
    if (length(regions) < 2) {
      stop("Error: The regions object must contain at least two sets of genomic regions.")
    }
    
    # -----------------------------------------------------------------
    # 2. Initialize Separate metagene2 Objects
    # -----------------------------------------------------------------
    mg1 <- metagene2\$new(bam_files = bam_files, 
                         regions = regions[1])
    
    mg2 <- metagene2\$new(bam_files = bam_files,
                         regions = regions[2])
    
    # -----------------------------------------------------------------
    # 3. Extract, Add Metadata, and Combine Data Frames
    # -----------------------------------------------------------------
    combined_df <- rbind(mg1\$add_metadata(), mg2\$add_metadata())
    
    # -----------------------------------------------------------------
    # 4. Plot Combined Data
    # -----------------------------------------------------------------
    p <- plot_metagene(combined_df,
                       facet_by=.~region_name)
    
    # -----------------------------------------------------------------
    # 5. Write Named Output Files
    # -----------------------------------------------------------------
    # Save the combined data frame as CSV and RDS
    write.csv(combined_df, "metagene_combined_metadata.csv", row.names = FALSE)
    saveRDS(combined_df, "metagene_combined_metadata.rds")
    
    # Save the generated plot as a PDF
    ggsave("metagene_plot.pdf", plot = p, width = 10, height = 8)
    
    # Save individual metagene objects for reproducibility
    saveRDS(mg1, "metagene_object_1.rds")
    saveRDS(mg2, "metagene_object_2.rds")

    writeLines(c(
        '"BIOC_METAGENE2_LARGE_DATASET_ANALYSIS":',
        paste0('    metagene2: ', as.character(packageVersion('metagene2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_large_dataset_analysis.csv versions.yml
    """
}

workflow BIOC_METAGENE2_LARGE_DATASET_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_files, regions ] ]

    main:
    BIOC_METAGENE2_LARGE_DATASET_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METAGENE2_LARGE_DATASET_ANALYSIS.out.tables
    plots    = BIOC_METAGENE2_LARGE_DATASET_ANALYSIS.out.plots
    objects  = BIOC_METAGENE2_LARGE_DATASET_ANALYSIS.out.objects
    versions = BIOC_METAGENE2_LARGE_DATASET_ANALYSIS.out.versions
}
