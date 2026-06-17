#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dmrseq — block_detection
// Detect large-scale, lower-resolution methylation blocks across the genome by adjusting smoothing and gap parameters.
// Input: sample_metadata.csv, bs_object.rds
// Container: quay.io/biocontainers/bioconductor-dmrseq:1.30.0--r45hdfd78af_0
// R packages: bsseq, dmrseq
// Bioconductor: 3.20 | R: 4.4
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
    .bm_deps <- c("bsseq", "dmrseq")
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
