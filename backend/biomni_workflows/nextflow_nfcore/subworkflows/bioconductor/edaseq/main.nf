#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: edaseq — read_level_qc
// Perform quality control and exploratory data analysis on raw unaligned reads (FASTQ) and aligned reads (BAM).
// Input: file1.fastq, file2.bam
// Container: quay.io/biocontainers/bioconductor-edaseq:2.44.0--r45hdfd78af_0
// R packages: Rsamtools, ShortRead, DESeq2, EDASeq, edgeR, leebamviews, yeastrnaseq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: bar plot

nextflow.enable.dsl = 2

process BIOC_EDASEQ_READ_LEVEL_QC {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-edaseq:2.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("Rsamtools", "ShortRead", "DESeq2", "EDASeq", "edgeR", "leebamviews", "yeastrnaseq")
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
    library(EDASeq)
    library(ShortRead)
    library(Rsamtools)
    
    # --- Identify and list raw FASTQ or aligned BAM files ---
    # The pipeline reads exactly "file1.fastq" and "file2.bam" from the working directory.
    fastq_file <- "file1.fastq"
    bam_file <- "file2.bam"
    
    if (!file.exists(fastq_file)) {
      stop("Required input file 'file1.fastq' not found in the working directory.")
    }
    if (!file.exists(bam_file)) {
      stop("Required input file 'file2.bam' not found in the working directory.")
    }
    
    # --- Construct FastqFileList or BamFileList objects and attach ---
    # FASTQ File List Setup
    files_fastq <- fastq_file
    names(files_fastq) <- gsub("\\\\.fastq.*", "", basename(files_fastq))
    met <- DataFrame(conditions = "wt", row.names = names(files_fastq))
    fastq <- FastqFileList(files_fastq)
    elementMetadata(fastq) <- met
    
    # BAM File List Setup
    files_bam <- bam_file
    names(files_bam) <- gsub("\\\\.bam", "", basename(files_bam))
    gt <- gsub(".*/", "", files_bam)
    gt <- gsub("_.*", "", gt)
    lane <- gsub(".*(.)\$", "\\1", gt)
    geno <- gsub(".\$", "", gt)
    pd <- DataFrame(geno = geno, lane = lane, row.names = paste(geno, lane, sep = "."))
    bfs <- BamFileList(files_bam)
    elementMetadata(bfs) <- pd
    
    # Save the constructed objects as RDS files
    saveRDS(fastq, file = "fastq_file_list.rds")
    saveRDS(bfs, file = "bam_file_list.rds")
    
    # Write metadata tables to CSV
    write.csv(as.data.frame(elementMetadata(fastq)), file = "fastq_metadata.csv", row.names = TRUE)
    write.csv(as.data.frame(elementMetadata(bfs)), file = "bam_metadata.csv", row.names = TRUE)
    
    # Define colors as specified in the documented code
    colors <- c(rep(rgb(1,0,0,alpha=0.7),2), rep(rgb(0,0,1,alpha=0.7),2), rep(rgb(0,1,0,alpha=0.7),2), rep(rgb(0,1,1,alpha=0.7),2))
    
    # Open PDF device to save the plots
    pdf("read_level_qc_plots.pdf", width = 8, height = 6)
    
    # --- Generate barplots of total or mapped read counts per lane ---
    barplot(bfs,las=2,col=colors)
    
    # --- Plot mean per-base quality scores across sequencing cycles ---
    plotQuality(bfs,col=colors,lty=1)
    legend("topright",unique(elementMetadata(bfs)[,1]), fill=unique(colors))
    
    plotQuality(bfs[[1]],cex.axis=.8)
    barplot(bfs[[1]],las=2)
    
    # --- Plot per-base nucleotide frequencies to check for ---
    plotNtFrequency(bfs[[1]])
    
    # Close the PDF device
    dev.off()

    writeLines(c(
        '"BIOC_EDASEQ_READ_LEVEL_QC":',
        paste0('        edaseq: ', as.character(packageVersion("edaseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_read_level_qc.csv versions.yml
    """
}

workflow BIOC_EDASEQ_READ_LEVEL_QC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file1.fastq, file2.bam ] ]

    main:
    BIOC_EDASEQ_READ_LEVEL_QC(ch_input)

    emit:
    tables   = BIOC_EDASEQ_READ_LEVEL_QC.out.tables
    plots    = BIOC_EDASEQ_READ_LEVEL_QC.out.plots
    objects  = BIOC_EDASEQ_READ_LEVEL_QC.out.objects
    versions = BIOC_EDASEQ_READ_LEVEL_QC.out.versions
}
