#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hmmcopy — single_sample_correction_and_segmentation
// Correct GC and mappability biases in a single sample and segment the copy number profile.
// Input: tumour.wig, gc.wig, map.wig
// Container: quay.io/biocontainers/bioconductor-hmmcopy:1.52.0--r45h01b2380_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HMMCOPY_SINGLE_SAMPLE_CORRECTION_AND_SEGMENTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-hmmcopy:1.52.0--r45h01b2380_0"

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
    .bm_deps <- c("hmmcopy")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Set options and load required library
    options(stringsAsFactors = TRUE)
    library(HMMcopy)
    
    # Define input file paths in the working directory
    tfile <- "tumour.wig"
    gfile <- "gc.wig"
    mfile <- "map.wig"
    
    # Verify that all required input files exist
    if (!file.exists(tfile)) {
      stop("Error: Input file 'tumour.wig' not found in the working directory.")
    }
    if (!file.exists(gfile)) {
      stop("Error: Input file 'gc.wig' not found in the working directory.")
    }
    if (!file.exists(mfile)) {
      stop("Error: Input file 'map.wig' not found in the working directory.")
    }
    
    # 1. Load and correct read counts using wigsToRangedData and correctReadcount
    message("Loading and correcting read counts...")
    tumour_copy <- correctReadcount(wigsToRangedData(tfile, gfile, mfile))
    
    # 2. Segment the corrected copy number profile using HMMsegment
    message("Segmenting copy number profile...")
    tumour_segments <- HMMsegment(tumour_copy)
    
    # 3. Visualize the segments and states using plotSegments and stateCols
    message("Generating visualization plot...")
    pdf("tumour_segments_plot.pdf", width = 10, height = 6)
    plotSegments(tumour_copy, tumour_segments, pch = ".", ylab = "Tumour Copy Number", xlab = "Chromosome Position")
    cols <- stateCols()
    legend("topleft", c("HOMD", "HETD", "NEUT", "GAIN", "AMPL", "HLAMP"), fill = cols, horiz = TRUE, bty = "n", cex = 0.5)
    dev.off()
    
    # 4. Write named output files for the results
    message("Saving output files...")
    
    # Save corrected copy number profile
    saveRDS(tumour_copy, "tumour_copy.rds")
    write.csv(as.data.frame(tumour_copy), "tumour_copy.csv", row.names = FALSE)
    
    # Save segmentation results
    saveRDS(tumour_segments, "tumour_segments.rds")
    if (!is.null(tumour_segments\$segs)) {
      write.csv(tumour_segments\$segs, "tumour_segments.csv", row.names = FALSE)
    }
    
    message("Pipeline completed successfully. Outputs saved to 'tumour_copy.rds', 'tumour_copy.csv', 'tumour_segments.rds', 'tumour_segments.csv', and 'tumour_segments_plot.pdf'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_HMMCOPY_SINGLE_SAMPLE_CORRECTION_AND_SEGMENTATION":
        hmmcopy: \$(Rscript -e 'cat(as.character(packageVersion("hmmcopy")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_correction_and_segmentation.csv versions.yml
    """
}

workflow BIOC_HMMCOPY_SINGLE_SAMPLE_CORRECTION_AND_SEGMENTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tumour.wig, gc.wig, map.wig ] ]

    main:
    BIOC_HMMCOPY_SINGLE_SAMPLE_CORRECTION_AND_SEGMENTATION(ch_input)

    emit:
    tables   = BIOC_HMMCOPY_SINGLE_SAMPLE_CORRECTION_AND_SEGMENTATION.out.tables
    plots    = BIOC_HMMCOPY_SINGLE_SAMPLE_CORRECTION_AND_SEGMENTATION.out.plots
    objects  = BIOC_HMMCOPY_SINGLE_SAMPLE_CORRECTION_AND_SEGMENTATION.out.objects
    versions = BIOC_HMMCOPY_SINGLE_SAMPLE_CORRECTION_AND_SEGMENTATION.out.versions
}
