#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scTHI — tme_classification
// Classify non-tumor cells in the tumor microenvironment into specific immune and stromal cell types using gene signature enrichment.
// Input: expMat, tsneData
// Container: quay.io/biocontainers/bioconductor-scthi:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: scTHI
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Subset expression matrix to TME cells
//  * 2. [Core Analysis] Run TME_classification to classify cells
//  * 3. [Visualization & Output] Plot the classification results on t-SNE coordinates using TME_plot

nextflow.enable.dsl = 2

process BIOC_SCTHI_TME_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(scTHI)
    
    # -------------------------------------------------------------------------
    # 1. Read User Input Files
    # -------------------------------------------------------------------------
    
    # Read expMat
    if (file.exists("expMat.rds")) {
      expMat <- readRDS("expMat.rds")
    } else if (file.exists("expMat.csv")) {
      expMat <- as.matrix(read.csv("expMat.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("expMat.tsv")) {
      expMat <- as.matrix(read.delim("expMat.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: expMat file not found in the working directory (expected expMat.rds, expMat.csv, or expMat.tsv).")
    }
    
    # Read tsneData
    if (file.exists("tsneData.rds")) {
      tsneData <- readRDS("tsneData.rds")
    } else if (file.exists("tsneData.csv")) {
      tsneData <- as.matrix(read.csv("tsneData.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("tsneData.tsv")) {
      tsneData <- as.matrix(read.delim("tsneData.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: tsneData file not found in the working directory (expected tsneData.rds, tsneData.csv, or tsneData.tsv).")
    }
    
    # Ensure tsneData has rownames matching expMat columns
    if (is.null(rownames(tsneData))) {
      rownames(tsneData) <- colnames(expMat)[1:nrow(tsneData)]
    }
    
    # -------------------------------------------------------------------------
    # 2. Subset expression matrix to TME cells
    # -------------------------------------------------------------------------
    # We define Tme.cells based on the intersection of expMat columns and tsneData rows
    Tme.cells <- intersect(colnames(expMat), rownames(tsneData))
    if (length(Tme.cells) == 0) {
      Tme.cells <- colnames(expMat)
    }
    
    H3K27.tme <- expMat[, Tme.cells, drop = FALSE]
    
    # Prepare H3K27.result list to match the documented code's structure
    H3K27.result <- list(tsneData = tsneData[Tme.cells, , drop = FALSE])
    
    # -------------------------------------------------------------------------
    # 3. Run TME_classification to classify cells
    # -------------------------------------------------------------------------
    Class <- TME_classification(expMat = H3K27.tme, minLenGeneSet = 10)
    
    # -------------------------------------------------------------------------
    # 4. Plot the classification results on t-SNE coordinates using TME_plot
    # -------------------------------------------------------------------------
    pdf("TME_classification_plot.pdf", width = 10, height = 8)
    TME_plot(tsneData = H3K27.result\$tsneData, Class, cexPoint = 0.8)
    dev.off()
    
    # -------------------------------------------------------------------------
    # 5. Save Outputs
    # -------------------------------------------------------------------------
    saveRDS(Class, "TME_classification_results.rds")
    
    if (is.data.frame(Class)) {
      write.csv(Class, "TME_classification_results.csv", row.names = TRUE)
    } else {
      tryCatch({
        write.csv(as.data.frame(Class), "TME_classification_results.csv", row.names = TRUE)
      }, error = function(e) {
        # Fallback if Class is a list but not directly coercible to data.frame
      })
    }

    writeLines(c(
        '"BIOC_SCTHI_TME_CLASSIFICATION":',
        paste0('    scTHI: ', as.character(packageVersion('scTHI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tme_classification.csv versions.yml
    """
}

workflow BIOC_SCTHI_TME_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expMat, tsneData ] ]

    main:
    BIOC_SCTHI_TME_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_SCTHI_TME_CLASSIFICATION.out.tables
    plots    = BIOC_SCTHI_TME_CLASSIFICATION.out.plots
    objects  = BIOC_SCTHI_TME_CLASSIFICATION.out.objects
    versions = BIOC_SCTHI_TME_CLASSIFICATION.out.versions
}
