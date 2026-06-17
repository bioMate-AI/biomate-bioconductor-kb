#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metagene2 — rnaseq_metagene_analysis
// Perform RNA-seq metagene analysis by stitching exons together and using strand-specific coverage.
// Input: bam_files, regions
// Container: quay.io/biocontainers/bioconductor-metagene2:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, metagene2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Initialize metagene2 Object (Stitch Mode)
//  * 3. [Visualization & Output] Produce Metagene Plot and Save Outputs

nextflow.enable.dsl = 2

process BIOC_METAGENE2_RNASEQ_METAGENE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("metagene2", "GenomicRanges")
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
    library(metagene2)
    library(GenomicRanges)
    
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    
    # Read the GRangesList of exons grouped by gene/transcript
    if (!file.exists("regions.rds")) {
        stop("Error: 'regions.rds' containing the GRangesList of exons was not found in the working directory.")
    }
    regions <- readRDS("regions.rds")
    
    # Identify indexed BAM files in the working directory
    bam_files <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    # Exclude index files if they were captured by the pattern
    bam_files <- bam_files[!grepl("\\\\.bai\$", bam_files)]
    
    if (length(bam_files) == 0) {
        stop("Error: No BAM files found in the working directory.")
    }
    
    # Verify that index files (.bai) exist for each BAM file
    for (bam in bam_files) {
        if (!file.exists(paste0(bam, ".bai")) && !file.exists(gsub("\\\\.bam\$", ".bai", bam))) {
            stop(paste("Error: Missing index file (.bai) for BAM file:", bam))
        }
    }
    
    # ==========================================
    # --- Initialize metagene2 Object (Stitch Mode) ---
    # ==========================================
    
    # Initialize the metagene2 object using the exact documented arguments
    mg <- metagene2\$new(regions = regions,
                        bam_files = bam_files,
                        region_mode = "stitch",
                        assay = "rnaseq")
    
    # Retrieve and save the post-processed regions
    processed_regions <- mg\$get_regions()
    saveRDS(processed_regions, "processed_regions.rds")
    
    # ==========================================
    # --- Produce Metagene Plot and Save Outputs ---
    # ==========================================
    
    # Generate and save the metagene plot to a PDF file
    pdf("rnaseq_metagene_plot.pdf", width = 10, height = 8)
    p <- mg\$produce_metagene(title = "RNA-seq Metagene Analysis (Stitched Exons)")
    print(p)
    dev.off()
    
    # Extract and save the underlying data table used for the plot
    df_plot <- mg\$add_metadata()
    write.csv(df_plot, "rnaseq_metagene_data.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_METAGENE2_RNASEQ_METAGENE_ANALYSIS":',
        paste0('    metagene2: ', as.character(packageVersion('metagene2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseq_metagene_analysis.csv versions.yml
    """
}

workflow BIOC_METAGENE2_RNASEQ_METAGENE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_files, regions ] ]

    main:
    BIOC_METAGENE2_RNASEQ_METAGENE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METAGENE2_RNASEQ_METAGENE_ANALYSIS.out.tables
    plots    = BIOC_METAGENE2_RNASEQ_METAGENE_ANALYSIS.out.plots
    objects  = BIOC_METAGENE2_RNASEQ_METAGENE_ANALYSIS.out.objects
    versions = BIOC_METAGENE2_RNASEQ_METAGENE_ANALYSIS.out.versions
}
