#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CRImage — copy_number_correction
// Correct DNA copy number log-ratios (LRR) and beta allele frequencies (BAF) for tumor cellularity.
// Input: z
// Container: quay.io/biocontainers/bioconductor-crimage:1.58.0--r45hdfd78af_0
// Requires: CRImage
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Correct copy number values for a given tumor purity/cellularity using correctCopyNumber
//  * 2. [Visualization & Output] Plot the corrected copy number profiles using plotCorrectedCN

nextflow.enable.dsl = 2

process BIOC_CRIMAGE_COPY_NUMBER_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load the required library
    library(CRImage)
    
    # Read the user input file 'z' from the working directory
    # The pipeline checks for 'z', 'z.csv', or 'z.txt'
    if (file.exists("z")) {
      z <- read.table("z", header=TRUE, stringsAsFactors=FALSE)
    } else if (file.exists("z.csv")) {
      z <- read.csv("z.csv", stringsAsFactors=FALSE)
    } else if (file.exists("z.txt")) {
      z <- read.table("z.txt", header=TRUE, stringsAsFactors=FALSE)
    } else {
      stop("Error: Input file 'z' (or 'z.csv'/'z.txt') containing genomic coordinates, LRR, and BAF values was not found in the working directory.")
    }
    
    # 1. Correct copy number values for a given tumor purity/cellularity
    res <- correctCopyNumber(arr="Sample1", chr=1, p=0.75, z=z)
    
    # Save the corrected copy number results
    saveRDS(res, file="corrected_cn_results.rds")
    
    # If the result is a data frame or list of data frames, export to CSV
    if (is.data.frame(res)) {
      write.csv(res, "corrected_cn_results.csv", row.names=FALSE)
    } else if (is.list(res)) {
      for (name in names(res)) {
        if (is.data.frame(res[[name]])) {
          write.csv(res[[name]], paste0("corrected_cn_", name, ".csv"), row.names=FALSE)
        }
      }
    }
    
    # 2. Plot the corrected copy number profiles and save to PDF
    pdf("corrected_cn_plot.pdf", width=10, height=6)
    plotCorrectedCN(res, chr=1)
    dev.off()

    writeLines(c(
        '"BIOC_CRIMAGE_COPY_NUMBER_CORRECTION":',
        paste0('    CRImage: ', as.character(packageVersion('CRImage')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_copy_number_correction.csv versions.yml
    """
}

workflow BIOC_CRIMAGE_COPY_NUMBER_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ z ] ]

    main:
    BIOC_CRIMAGE_COPY_NUMBER_CORRECTION(ch_input)

    emit:
    tables   = BIOC_CRIMAGE_COPY_NUMBER_CORRECTION.out.tables
    plots    = BIOC_CRIMAGE_COPY_NUMBER_CORRECTION.out.plots
    objects  = BIOC_CRIMAGE_COPY_NUMBER_CORRECTION.out.objects
    versions = BIOC_CRIMAGE_COPY_NUMBER_CORRECTION.out.versions
}
