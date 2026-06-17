#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: repviz — replicate_sequencing_visualization
// Visualize replicate-level and group-level sequencing counts alongside genomic features and gene tracks for a specific genomic region.
// Input: BAM_input.csv, BED_input.csv, BAM and BAI files, BED files
// Container: quay.io/biocontainers/bioconductor-repviz:1.22.0--r44hdfd78af_0
// R packages: GenomicRanges, RepViz
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REPVIZ_REPLICATE_SEQUENCING_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-repviz:1.22.0--r44hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "RepViz")
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
    library(GenomicRanges)
    library(RepViz)
    
    # Define input file paths (expected to be in the working directory)
    bam_input_csv <- "BAM_input.csv"
    bed_input_csv <- "BED_input.csv"
    
    # Verify that the required input files exist before proceeding
    if (!file.exists(bam_input_csv)) {
      stop(paste("Required input file missing:", bam_input_csv))
    }
    if (!file.exists(bed_input_csv)) {
      stop(paste("Required input file missing:", bed_input_csv))
    }
    
    # --- Define the genomic region of interest using GenomicRanges ---
    region <- GRanges("chr12:110938000-110940000")
    
    # Set up PDF device to capture the generated visualization
    output_plot <- "replicate_visualization.pdf"
    pdf(output_plot, width = 8, height = 10)
    
    # --- Run the RepViz function to generate the multi-panel ---
    RepViz::RepViz(region = region,
        genome = "hg19",
        BAM = "BAM_input.csv",
        BED = "BED_input.csv",
        avgTrack = TRUE,
        geneTrack = TRUE,
        verbose = FALSE)
    
    # Close the plotting device
    dev.off()
    
    # Save the region object as an RDS file for downstream tracking
    saveRDS(region, file = "visualized_region.rds")

    writeLines(c(
        '"BIOC_REPVIZ_REPLICATE_SEQUENCING_VISUALIZATION":',
        paste0('        repviz: ', as.character(packageVersion("repviz")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_replicate_sequencing_visualization.csv versions.yml
    """
}

workflow BIOC_REPVIZ_REPLICATE_SEQUENCING_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BAM_input.csv, BED_input.csv, BAM and BAI files, BED files ] ]

    main:
    BIOC_REPVIZ_REPLICATE_SEQUENCING_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_REPVIZ_REPLICATE_SEQUENCING_VISUALIZATION.out.tables
    plots    = BIOC_REPVIZ_REPLICATE_SEQUENCING_VISUALIZATION.out.plots
    objects  = BIOC_REPVIZ_REPLICATE_SEQUENCING_VISUALIZATION.out.objects
    versions = BIOC_REPVIZ_REPLICATE_SEQUENCING_VISUALIZATION.out.versions
}
