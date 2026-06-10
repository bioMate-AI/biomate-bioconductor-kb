#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: edaseq — read_level_qc
// Perform quality control and exploratory data analysis on raw unaligned reads (FASTQ) and aligned reads (BAM).
// Input: file1.fastq, file2.bam
// Container: quay.io/biocontainers/bioconductor-edaseq:2.44.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

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
    .bm_deps <- c("Rsamtools", "ShortRead", "deseq2", "edaseq", "edger", "leebamviews", "yeastrnaseq")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(EDASeq)
    library(ShortRead)
    library(Rsamtools)
    
    # 1. Identify and list raw FASTQ or aligned BAM files.
    # The pipeline reads exactly "file1.fastq" and "file2.bam" from the working directory.
    fastq_file <- "file1.fastq"
    bam_file <- "file2.bam"
    
    if (!file.exists(fastq_file)) {
      stop("Required input file 'file1.fastq' not found in the working directory.")
    }
    if (!file.exists(bam_file)) {
      stop("Required input file 'file2.bam' not found in the working directory.")
    }
    
    # 2. Construct FastqFileList or BamFileList objects and attach sample metadata.
    # FASTQ File List Setup
    files_fastq <- fastq_file
    names(files_fastq) <- gsub("\\.fastq.*", "", basename(files_fastq))
    met <- DataFrame(conditions = "wt", row.names = names(files_fastq))
    fastq <- FastqFileList(files_fastq)
    elementMetadata(fastq) <- met
    
    # BAM File List Setup
    files_bam <- bam_file
    names(files_bam) <- gsub("\\.bam", "", basename(files_bam))
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
    
    # 3. Generate barplots of total or mapped read counts per lane.
    barplot(bfs,las=2,col=colors)
    
    # 4. Plot mean per-base quality scores across sequencing cycles.
    plotQuality(bfs,col=colors,lty=1)
    legend("topright",unique(elementMetadata(bfs)[,1]), fill=unique(colors))
    
    plotQuality(bfs[[1]],cex.axis=.8)
    barplot(bfs[[1]],las=2)
    
    # 5. Plot per-base nucleotide frequencies to check for sequence composition bias.
    plotNtFrequency(bfs[[1]])
    
    # Close the PDF device
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_EDASEQ_READ_LEVEL_QC":
        edaseq: \$(Rscript -e 'cat(as.character(packageVersion("edaseq")))')
    END_VERSIONS
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
