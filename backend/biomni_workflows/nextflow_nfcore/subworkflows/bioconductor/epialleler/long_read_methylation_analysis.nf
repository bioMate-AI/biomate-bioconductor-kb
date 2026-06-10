#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epialleler — long_read_methylation_analysis
// Preprocess long-read BAM files (with MM/ML tags) and generate cytosine-level reports and methylation patterns.
// Input: longread.bam, long.bed
// Container: quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0"

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
    .bm_deps <- c("GenomicRanges", "epialleleR", "rtracklayer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(epialleleR)
    library(rtracklayer)
    library(GenomicRanges)
    
    # 1. Load the target region (long.bed)
    # Robust loading: try RDS first, then BED import
    if (file.exists("long.bed")) {
      long.bed <- tryCatch({
        readRDS("long.bed")
      }, error = function(e) {
        rtracklayer::import("long.bed")
      })
    } else {
      stop("Required input file 'long.bed' not found in the working directory.")
    }
    
    # Verify BAM file exists
    if (!file.exists("longread.bam")) {
      stop("Required input file 'longread.bam' not found in the working directory.")
    }
    
    # 2. Preprocess long-read BAM using preprocessBam with quality and probability filters
    message("Preprocessing long-read BAM...")
    longread.data <- preprocessBam("longread.bam", min.mapq=30, min.baseq=20, min.prob=178)
    
    # 3. Generate cytosine-level report using generateCytosineReport with threshold.reads=FALSE
    message("Generating cytosine report...")
    cytosine.report <- generateCytosineReport(longread.data, threshold.reads=FALSE)
    
    # Save cytosine report
    write.csv(cytosine.report, "cytosine_report.csv", row.names=FALSE)
    message("Cytosine report saved to 'cytosine_report.csv'.")
    
    # 4. Extract and plot methylation patterns using extractPatterns and plotPatterns
    message("Preprocessing BAM with target regions...")
    long.bam <- "longread.bam"
    long.data <- preprocessBam(bam=long.bam, targets=long.bed, clip.to.targets=TRUE, min.mapq=30, min.baseq=20, min.prob=178)
    
    message("Extracting methylation patterns...")
    patterns <- extractPatterns(bam=long.data, bed=long.bed)
    
    # Save patterns object
    saveRDS(patterns, "extracted_patterns.rds")
    message("Extracted patterns saved to 'extracted_patterns.rds'.")
    
    # Plot patterns to PDF
    message("Plotting patterns...")
    pdf("methylation_patterns.pdf", width=10, height=6)
    plotPatterns(patterns, npatterns.per.bin=Inf)
    dev.off()
    message("Methylation patterns plot saved to 'methylation_patterns.pdf'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS":
        epialleler: \$(Rscript -e 'cat(as.character(packageVersion("epialleler")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_long_read_methylation_analysis.csv versions.yml
    """
}

workflow BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ longread.bam, long.bed ] ]

    main:
    BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS.out.tables
    plots    = BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS.out.plots
    objects  = BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS.out.objects
    versions = BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS.out.versions
}
