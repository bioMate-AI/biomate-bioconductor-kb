#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scruff — read_mapping_visualization
// Visualize read alignment locations and gene models at specified genomic coordinates.
// Input: alignments.bam, reference.gtf
// Container: quay.io/biocontainers/bioconductor-scruff:1.28.0--r45hdfd78af_0
// R packages: BiocGenerics, GenomeInfoDb, GenomicAlignments, ggplot2, patchwork, scruff
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCRUFF_READ_MAPPING_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-scruff:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("BiocGenerics", "GenomeInfoDb", "GenomicAlignments", "ggplot2", "patchwork", "scruff")
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
    library(scruff)
    library(patchwork)
    library(GenomicAlignments)
    library(ggplot2)
    library(BiocGenerics)
    library(GenomeInfoDb)
    
    # Define input file paths
    bam_file <- "alignments.bam"
    gtf_file <- "reference.gtf"
    
    # Read BAM file as GAlignments object
    message("Reading alignments.bam...")
    bamExample <- GenomicAlignments::readGAlignments(bam_file, use.names = TRUE)
    
    # Set GTF path
    gtf <- gtf_file
    
    # Determine genomic coordinates dynamically from the BAM file
    if (length(bamExample) > 0) {
        chr <- as.character(GenomeInfoDb::seqnames(bamExample)[1])
        # Use a window around the first aligned read
        first_start <- BiocGenerics::start(bamExample)[1]
        start <- max(1, first_start - 100)
        end <- first_start + 2000
        message(sprintf("Using dynamic coordinates: chr=%s, start=%d, end=%d", chr, start, end))
    } else {
        chr <- "MT"
        start <- 1094
        end <- 2675
        message(sprintf("BAM is empty. Using default coordinates: chr=%s, start=%d, end=%d", chr, start, end))
    }
    
    # 1. Visualize reads using rview
    message("Visualizing read alignment locations...")
    g1 <- rview(bamExample, chr = chr, start = start, end = end) + 
        ggplot2::scale_x_continuous(limits = c(start, end))
    
    # 2. Visualize gene models using gview
    message("Visualizing gene models...")
    g2 <- gview(gtf, chr = chr, start = start, end = end) + 
        ggplot2::scale_x_continuous(limits = c(start, end))
    
    # 3. Combine plots using patchwork
    message("Combining plots...")
    g <- (g1 + ggplot2::theme(axis.title.x = ggplot2::element_blank(), 
                             axis.text.x = ggplot2::element_blank(), 
                             plot.margin = ggplot2::margin(t = 0, b = 0))) / 
         (g2 + ggplot2::theme(plot.margin = ggplot2::margin(t = 0, b = 0))) / 
         patchwork::plot_layout(ncol = 1, heights = c(4, 1))
    
    # Save outputs
    message("Saving output files...")
    ggplot2::ggsave("read_mapping_visualization.pdf", plot = g, width = 10, height = 8)
    saveRDS(g, "read_mapping_visualization.rds")
    
    message("Pipeline completed successfully!")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SCRUFF_READ_MAPPING_VISUALIZATION":
        scruff: \$(Rscript -e 'cat(as.character(packageVersion("scruff")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_read_mapping_visualization.csv versions.yml
    """
}

workflow BIOC_SCRUFF_READ_MAPPING_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ alignments.bam, reference.gtf ] ]

    main:
    BIOC_SCRUFF_READ_MAPPING_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SCRUFF_READ_MAPPING_VISUALIZATION.out.tables
    plots    = BIOC_SCRUFF_READ_MAPPING_VISUALIZATION.out.plots
    objects  = BIOC_SCRUFF_READ_MAPPING_VISUALIZATION.out.objects
    versions = BIOC_SCRUFF_READ_MAPPING_VISUALIZATION.out.versions
}
