#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NanoMethViz — modbam_direct_plotting
// Directly visualize methylation from modBAM files without converting to tabix format.
// Input: peg3.bam, sample_anno.csv
// Container: quay.io/biocontainers/bioconductor-nanomethviz:2.8.1--r43hf17093f_0
// R packages: NanoMethViz, dplyr
// Bioconductor: 3.20 | R: 4.4
// Requires: NanoMethViz, dplyr
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define ModBamFiles with sample names and BAM paths
//  * 2. [Input & Preparation] Construct ModBamResult object
//  * 3. [Visualization & Output] Plot methylation patterns using plot_gene()

nextflow.enable.dsl = 2

process BIOC_NANOMETHVIZ_MODBAM_DIRECT_PLOTTING {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("NanoMethViz", "dplyr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    library(NanoMethViz)
    library(dplyr)
    
    # Read user input files from the working directory
    sample_anno <- read.csv("sample_anno.csv", stringsAsFactors = FALSE)
    bam_file <- "peg3.bam"
    
    # Retrieve exon annotations using the package's helper function
    exon_tibble <- get_exons_mm10()
    
    # Construct the ModBamResult object using the documented structure
    mbr <- ModBamResult(
        methy = ModBamFiles(
            samples = sample_anno\$sample[1],
            bam_file
        ),
        samples = sample_anno,
        exons = exon_tibble
    )
    
    # Save the constructed ModBamResult object to disk
    saveRDS(mbr, "modbam_result.rds")
    
    # Generate and save the methylation plot to a PDF file
    pdf("peg3_methylation_heatmap.pdf", width = 10, height = 8)
    plot_gene(mbr, "Peg3", heatmap = TRUE)
    dev.off()

    writeLines(c(
        '"BIOC_NANOMETHVIZ_MODBAM_DIRECT_PLOTTING":',
        paste0('    NanoMethViz: ', as.character(packageVersion('NanoMethViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_modbam_direct_plotting.csv versions.yml
    """
}

workflow BIOC_NANOMETHVIZ_MODBAM_DIRECT_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peg3.bam, sample_anno.csv ] ]

    main:
    BIOC_NANOMETHVIZ_MODBAM_DIRECT_PLOTTING(ch_input)

    emit:
    tables   = BIOC_NANOMETHVIZ_MODBAM_DIRECT_PLOTTING.out.tables
    plots    = BIOC_NANOMETHVIZ_MODBAM_DIRECT_PLOTTING.out.plots
    objects  = BIOC_NANOMETHVIZ_MODBAM_DIRECT_PLOTTING.out.objects
    versions = BIOC_NANOMETHVIZ_MODBAM_DIRECT_PLOTTING.out.versions
}
