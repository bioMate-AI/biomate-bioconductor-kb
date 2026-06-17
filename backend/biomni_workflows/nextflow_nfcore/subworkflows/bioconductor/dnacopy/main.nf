#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DNAcopy — dna_copy_number_segmentation
// Segment DNA copy number data to identify genomic regions with abnormal copy number using circular binary segmentation (CBS).
// Input: copy_number_data.txt
// Container: quay.io/biocontainers/bioconductor-dnacopy:1.86.0--r45h5bbb887_0
// R packages: DNAcopy
// Bioconductor: 3.20 | R: 4.4
// Requires: DNAcopy
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the DNAcopy package and import data into a CNA object using CNA()
//  * 2. [Core Analysis] Smooth single-point outliers using smooth.CNA()
//  * 3. [Core Analysis] Segment the smoothed data using segment()
//  * 4. [Visualization & Output] Visualize the segmented data using plot() with different plot.type options
//  * 5. [Visualization & Output] Refine segmentation by undoing splits with segment() using undo.splits="sdundo" and plot the results

nextflow.enable.dsl = 2

process BIOC_DNACOPY_DNA_COPY_NUMBER_SEGMENTATION {
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
    .bm_deps <- c("DNAcopy")
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
    
    # Load the DNAcopy package
    library(DNAcopy)
    
    # Read the user input file
    df <- read.delim("copy_number_data.txt", header = TRUE, sep = "\t")
    
    # Identify Chromosome, Position, and Sample columns dynamically
    chrom_idx <- grep("chrom", colnames(df), ignore.case = TRUE)
    if (length(chrom_idx) == 0) chrom_idx <- 1
    
    pos_idx <- grep("pos", colnames(df), ignore.case = TRUE)
    if (length(pos_idx) == 0) pos_idx <- 2
    
    sample_idx <- setdiff(seq_len(ncol(df)), c(chrom_idx, pos_idx))[1]
    if (is.na(sample_idx)) sample_idx <- 3
    
    chromosomes <- df[[chrom_idx]]
    positions <- df[[pos_idx]]
    logratios <- df[[sample_idx]]
    sample_name <- colnames(df)[sample_idx]
    
    # 1. Create CNA object
    CNA.object <- CNA(cbind(logratios),
                      chromosomes, positions,
                      data.type="logratio", sampleid=sample_name)
    
    # 2. Smooth single-point outliers
    smoothed.CNA.object <- smooth.CNA(CNA.object)
    
    # 3. Segment the smoothed data
    segment.smoothed.CNA.object <- segment(smoothed.CNA.object, verbose=1)
    
    # Save RDS of the segmented object and write segment results to CSV
    saveRDS(segment.smoothed.CNA.object, "segment_smoothed_CNA_object.rds")
    write.csv(segment.smoothed.CNA.object\$output, "segmented_copy_number.csv", row.names=FALSE)
    
    # 4. Visualize the segmented data using plot() with different plot.type options
    pdf("segmentation_plots.pdf", width=10, height=8)
    plot(segment.smoothed.CNA.object, plot.type="w")
    plot(segment.smoothed.CNA.object, plot.type="s") 
    plot(segment.smoothed.CNA.object, plot.type="p")
    dev.off()
    
    # 5. Refine segmentation by undoing splits
    sdundo.CNA.object <- segment(smoothed.CNA.object, 
                                 undo.splits="sdundo", 
                                 undo.SD=3, verbose=1)
    
    # Save RDS of the refined segmented object and write refined segment results to CSV
    saveRDS(sdundo.CNA.object, "sdundo_CNA_object.rds")
    write.csv(sdundo.CNA.object\$output, "segmented_copy_number_sdundo.csv", row.names=FALSE)
    
    # Plot refined segmentation
    pdf("segmentation_plots_sdundo.pdf", width=10, height=8)
    plot(sdundo.CNA.object, plot.type="s")
    dev.off()

    writeLines(c(
        '"BIOC_DNACOPY_DNA_COPY_NUMBER_SEGMENTATION":',
        paste0('    DNAcopy: ', as.character(packageVersion('DNAcopy')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dna_copy_number_segmentation.csv versions.yml
    """
}

workflow BIOC_DNACOPY_DNA_COPY_NUMBER_SEGMENTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ copy_number_data.txt ] ]

    main:
    BIOC_DNACOPY_DNA_COPY_NUMBER_SEGMENTATION(ch_input)

    emit:
    tables   = BIOC_DNACOPY_DNA_COPY_NUMBER_SEGMENTATION.out.tables
    plots    = BIOC_DNACOPY_DNA_COPY_NUMBER_SEGMENTATION.out.plots
    objects  = BIOC_DNACOPY_DNA_COPY_NUMBER_SEGMENTATION.out.objects
    versions = BIOC_DNACOPY_DNA_COPY_NUMBER_SEGMENTATION.out.versions
}
