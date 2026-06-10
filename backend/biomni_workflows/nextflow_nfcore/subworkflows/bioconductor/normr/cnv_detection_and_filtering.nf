#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normr — cnv_detection_and_filtering
// Detect Copy Number Variations (CNVs) using input control tracks and filter differential ChIP-seq calls to remove CNV-driven false positives.
// Input: treatmentInput.bam, controlInput.bam, diffFit
// Container: quay.io/biocontainers/bioconductor-normr:1.36.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMR_CNV_DETECTION_AND_FILTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-normr:1.36.0--r45ha27e39d_0"

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
    .bm_deps <- c("GenomicRanges", "normr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library("normr")
    library("GenomicRanges")
    
    # 1. Declare and verify input files
    treatmentInputBamfile <- "treatmentInput.bam"
    controlInputBamfile <- "controlInput.bam"
    diffFitPath <- "diffFit"
    
    if (!file.exists(treatmentInputBamfile)) {
      stop(paste("Required treatment input BAM file missing:", treatmentInputBamfile))
    }
    if (!file.exists(controlInputBamfile)) {
      stop(paste("Required control input BAM file missing:", controlInputBamfile))
    }
    if (!file.exists(diffFitPath)) {
      # Try with .rds extension if the exact name is not found
      if (file.exists("diffFit.rds")) {
        diffFitPath <- "diffFit.rds"
      } else {
        stop("Required pre-calculated differential ChIP-seq fit object 'diffFit' (RDS format) missing.")
      }
    }
    
    # 2. Load the pre-calculated differential ChIP-seq fit object
    diffFit <- readRDS(diffFitPath)
    
    # 3. Extract genome information from the pre-calculated fit object
    # This ensures the genome specification matches the coordinates of the diffFit object.
    seq_info <- seqinfo(getRanges(diffFit))
    genome <- data.frame(
      chrom = seqnames(seq_info),
      size = seqlengths(seq_info),
      stringsAsFactors = FALSE
    )
    # Filter out any chromosomes with unresolved sizes
    genome <- genome[!is.na(genome\$size), ]
    
    # 4. Call differences between the two input control tracks to detect CNVs
    cnvs <- diffR(treatment   = treatmentInputBamfile,
                  control     = controlInputBamfile,
                  genome      = genome,
                  countConfig = countConfigSingleEnd(binsize = 2.5e4))
    
    # 5. Export the CNV calls
    exportR(cnvs, "CNVs.bed")
    
    # 6. Filter previous ChIP-seq difference calls for CNVs
    ov <- countOverlaps(getRanges(diffFit, fdr = .05), getRanges(cnvs, fdr = .05))
    idx <- which(ov == 0)
    cnvCleanedGR <- getRanges(diffFit, fdr = .05)[idx]
    
    # 7. Save meaningful outputs
    saveRDS(cnvs, "cnvs_fit.rds")
    saveRDS(cnvCleanedGR, "cnvCleanedGR.rds")
    write.csv(as.data.frame(cnvCleanedGR), "cnvCleanedGR.csv", row.names = FALSE)
    
    message("Pipeline completed successfully.")
    message("Outputs written: CNVs.bed, cnvs_fit.rds, cnvCleanedGR.rds, cnvCleanedGR.csv")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NORMR_CNV_DETECTION_AND_FILTERING":
        normr: \$(Rscript -e 'cat(as.character(packageVersion("normr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnv_detection_and_filtering.csv versions.yml
    """
}

workflow BIOC_NORMR_CNV_DETECTION_AND_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ treatmentInput.bam, controlInput.bam, diffFit ] ]

    main:
    BIOC_NORMR_CNV_DETECTION_AND_FILTERING(ch_input)

    emit:
    tables   = BIOC_NORMR_CNV_DETECTION_AND_FILTERING.out.tables
    plots    = BIOC_NORMR_CNV_DETECTION_AND_FILTERING.out.plots
    objects  = BIOC_NORMR_CNV_DETECTION_AND_FILTERING.out.objects
    versions = BIOC_NORMR_CNV_DETECTION_AND_FILTERING.out.versions
}
