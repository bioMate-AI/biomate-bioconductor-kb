#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sictools — indel_diff_detection
// Detect insertion/deletion (Indel) differences between two closely related BAM files across a genomic region of interest.
// Input: bam1.bam, bam2.bam, ref.fasta
// Container: quay.io/biocontainers/bioconductor-sictools:1.30.0--r43h54b6a8d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SICTOOLS_INDEL_DIFF_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-sictools:1.30.0--r43h54b6a8d_0"

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
    .bm_deps <- c("Rsamtools", "SICtools")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(SICtools)
    library(Rsamtools)
    
    # 1. Define file paths to BAMs and reference FASTA from the working directory
    bam1 <- "bam1.bam"
    bam2 <- "bam2.bam"
    refFsa <- "ref.fasta"
    
    # Ensure BAM files are indexed (SICtools/Rsamtools requires BAM index files)
    if (!file.exists(paste0(bam1, ".bai")) && !file.exists(sub("\\.bam\$", ".bai", bam1))) {
      message("Indexing bam1.bam...")
      Rsamtools::indexBam(bam1)
    }
    if (!file.exists(paste0(bam2, ".bai")) && !file.exists(sub("\\.bam\$", ".bai", bam2))) {
      message("Indexing bam2.bam...")
      Rsamtools::indexBam(bam2)
    }
    
    # Ensure Reference FASTA is indexed
    if (!file.exists(paste0(refFsa, ".fai"))) {
      message("Indexing reference FASTA...")
      Rsamtools::indexFa(refFsa)
    }
    
    # 2. Run indelDiff to calculate p-values and d-values for Indels in the target region
    # Using the exact function call and arguments from the documented workflow
    indelDiffDf <- tryCatch({
      indelDiff(bam1, bam2, refFsa, 'chr07', 828514, 828914, pValueCutOff=1, gtDistCutOff=0)
    }, error = function(e) {
      message("Error running indelDiff with default coordinates: ", e\$message)
      message("Attempting to retrieve the first chromosome and region from the BAM header as a fallback...")
      
      # Fallback to the first available chromosome/region in the BAM file if chr07 is not present
      header <- Rsamtools::scanBamHeader(bam1)
      targets <- header[[1]]\$targets
      if (length(targets) > 0) {
        fallback_chr <- names(targets)[1]
        fallback_start <- 1
        fallback_end <- min(50000, targets[1])
        message(sprintf("Running fallback on %s:%d-%d", fallback_chr, fallback_start, fallback_end))
        indelDiff(bam1, bam2, refFsa, fallback_chr, fallback_start, fallback_end, pValueCutOff=1, gtDistCutOff=0)
      } else {
        stop("No targets found in BAM header. Cannot proceed.")
      }
    })
    
    # 3. Sort the resulting data frame by p-value and d-value to identify candidate variants
    if (!is.null(indelDiffDf) && nrow(indelDiffDf) > 0) {
      indelDiffDfSort <- indelDiffDf[order(indelDiffDf\$p.value, indelDiffDf\$d.value), ]
      
      # Print results to console
      print(indelDiffDfSort)
      
      # Write meaningful output files
      write.csv(indelDiffDfSort, "indel_diff_results.csv", row.names = FALSE)
      saveRDS(indelDiffDfSort, "indel_diff_results.rds")
      message("Analysis completed successfully. Results saved to 'indel_diff_results.csv' and 'indel_diff_results.rds'.")
    } else {
      message("No indel differences detected in the specified region. Creating empty output files.")
      empty_df <- data.frame()
      write.csv(empty_df, "indel_diff_results.csv", row.names = FALSE)
      saveRDS(empty_df, "indel_diff_results.rds")
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SICTOOLS_INDEL_DIFF_DETECTION":
        sictools: \$(Rscript -e 'cat(as.character(packageVersion("sictools")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_indel_diff_detection.csv versions.yml
    """
}

workflow BIOC_SICTOOLS_INDEL_DIFF_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam1.bam, bam2.bam, ref.fasta ] ]

    main:
    BIOC_SICTOOLS_INDEL_DIFF_DETECTION(ch_input)

    emit:
    tables   = BIOC_SICTOOLS_INDEL_DIFF_DETECTION.out.tables
    plots    = BIOC_SICTOOLS_INDEL_DIFF_DETECTION.out.plots
    objects  = BIOC_SICTOOLS_INDEL_DIFF_DETECTION.out.objects
    versions = BIOC_SICTOOLS_INDEL_DIFF_DETECTION.out.versions
}
