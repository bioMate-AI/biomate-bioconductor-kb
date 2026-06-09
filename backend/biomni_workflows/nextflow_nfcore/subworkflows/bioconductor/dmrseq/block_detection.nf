#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dmrseq — block_detection
// Detect large-scale, lower-resolution methylation blocks across the genome by adjusting smoothing and gap parameters.
// Input: sample_metadata.csv, bs_object.rds
// Container: quay.io/biocontainers/bioconductor-dmrseq:1.30.0--r45hdfd78af_0
// Requires: bsseq, dmrseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run dmrseq with block = TRUE and increased smoothing parameters (minInSpan, bpSpan, maxGapSmooth, maxGap)
//  * 2. [Visualization & Output] Visualize the detected blocks using plotDMRs

nextflow.enable.dsl = 2

process BIOC_DMRSEQ_BLOCK_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    
    # Load required libraries
    library(dmrseq)
    library(bsseq)
    
    # 1. Read user input files
    metadata <- read.csv("sample_metadata.csv")
    bs <- readRDS("bs_object.rds")
    
    # Ensure the test covariate "CellType" is present in the BSseq object's pData
    if ("CellType" %in% colnames(metadata)) {
      pData(bs)\$CellType <- metadata\$CellType
    } else {
      # Fallback to the first column if "CellType" is not explicitly named
      pData(bs)\$CellType <- metadata[[1]]
    }
    
    # 2. Run dmrseq with block = TRUE and increased smoothing parameters
    testCovariate <- "CellType"
    blocks <- dmrseq(bs=bs,
                      cutoff = 0.05,
                      testCovariate=testCovariate,
                      block = TRUE,
                      minInSpan = 500,
                      bpSpan = 5e4,
                      maxGapSmooth = 1e6,
                      maxGap = 5e3)
    head(blocks)
    
    # 3. Retrieve annotations for visualization
    annoTrack <- tryCatch({
      getAnnot("hg19")
    }, error = function(e) {
      NULL
    })
    
    # 4. Visualize the detected blocks using plotDMRs
    if (length(blocks) > 0) {
      pdf("detected_blocks_plot.pdf", width = 10, height = 5)
      tryCatch({
        plotDMRs(bs, regions=blocks[1,], testCovariate="CellType",
            annoTrack=annoTrack)
      }, error = function(e) {
        message("Plotting failed: ", e\$message)
      })
      dev.off()
    } else {
      message("No blocks detected; skipping plot.")
    }
    
    # 5. Save outputs
    saveRDS(blocks, "detected_blocks.rds")
    write.csv(as.data.frame(blocks), "detected_blocks.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_DMRSEQ_BLOCK_DETECTION":',
        paste0('    dmrseq: ', as.character(packageVersion('dmrseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_block_detection.csv versions.yml
    """
}

workflow BIOC_DMRSEQ_BLOCK_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_metadata.csv, bs_object.rds ] ]

    main:
    BIOC_DMRSEQ_BLOCK_DETECTION(ch_input)

    emit:
    tables   = BIOC_DMRSEQ_BLOCK_DETECTION.out.tables
    plots    = BIOC_DMRSEQ_BLOCK_DETECTION.out.plots
    objects  = BIOC_DMRSEQ_BLOCK_DETECTION.out.objects
    versions = BIOC_DMRSEQ_BLOCK_DETECTION.out.versions
}
