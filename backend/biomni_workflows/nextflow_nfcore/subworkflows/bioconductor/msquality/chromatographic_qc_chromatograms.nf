#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MsQuality — chromatographic_qc_chromatograms
// Calculate quality metrics from chromatographic traces and peak shapes using Chromatograms objects.
// Input: chromatographic_data.csv
// Container: quay.io/biocontainers/bioconductor-msquality:1.10.0--r45hdfd78af_0
// R packages: BiocParallel, Chromatograms, MsExperiment, MsQuality, Spectra
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, Chromatograms, MsExperiment, MsQuality, Spectra
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load libraries
//  * 2. [Input & Preparation] Create a Chromatograms object
//  * 3. [Core Analysis] Retrieve available metrics using qualityMetrics()
//  * 4. [Core Analysis] Calculate metrics using calculateMetrics()

nextflow.enable.dsl = 2

process BIOC_MSQUALITY_CHROMATOGRAPHIC_QC_CHROMATOGRAMS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("BiocParallel", "Chromatograms", "MsExperiment", "MsQuality", "Spectra")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Expected columns in chromatographic_data.csv:
    # chromatogram_id, msLevel, mz, dataOrigin, rtime, intensity
    
    # 1. Load libraries
    library("Spectra")
    library("MsExperiment")
    library("Chromatograms")
    library("MsQuality")
    library("BiocParallel")
    
    # Register parallel backend
    register(SerialParam())
    
    # Read user input file
    input_file <- "chromatographic_data.csv"
    if (!file.exists(input_file)) {
        stop(paste("Required input file missing:", input_file))
    }
    
    chrom_data <- read.csv(input_file, stringsAsFactors = FALSE)
    
    # 2. Create a Chromatograms object
    # Group by chromatogram_id to split the rows into individual chromatograms
    chrom_list <- split(chrom_data, chrom_data\$chromatogram_id)
    
    cdata <- data.frame(
        msLevel = as.integer(sapply(chrom_list, function(x) x\$msLevel[1])),
        mz = as.numeric(sapply(chrom_list, function(x) x\$mz[1])),
        dataOrigin = as.character(sapply(chrom_list, function(x) x\$dataOrigin[1])),
        stringsAsFactors = FALSE
    )
    
    pdata <- lapply(chrom_list, function(x) {
        data.frame(
            rtime = as.numeric(x\$rtime),
            intensity = as.numeric(x\$intensity)
        )
    })
    names(pdata) <- NULL
    
    chr <- Chromatograms(ChromBackendMemory(), chromData = cdata, peaksData = pdata)
    
    # 3 & 4. Retrieve available metrics and calculate them
    metrics_chr <- calculateMetrics(object = chr, metrics = qualityMetrics(chr))
    
    # Write named output files
    write.csv(metrics_chr, "metrics_chromatograms.csv", row.names = TRUE)
    saveRDS(metrics_chr, "metrics_chromatograms.rds")
    
    # Generate diagnostic plot of the calculated metrics
    pdf("metrics_barplot.pdf", width = 10, height = 6)
    numeric_metrics <- metrics_chr[, sapply(metrics_chr, is.numeric), drop = FALSE]
    if (ncol(numeric_metrics) > 0) {
        par(mar = c(12, 4, 4, 2))
        barplot(as.matrix(numeric_metrics[1, ]),
                las = 2,
                main = "Chromatographic Quality Metrics",
                col = "skyblue",
                cex.names = 0.7)
    }
    dev.off()

    writeLines(c(
        '"BIOC_MSQUALITY_CHROMATOGRAPHIC_QC_CHROMATOGRAMS":',
        paste0('    MsQuality: ', as.character(packageVersion('MsQuality')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromatographic_qc_chromatograms.csv versions.yml
    """
}

workflow BIOC_MSQUALITY_CHROMATOGRAPHIC_QC_CHROMATOGRAMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chromatographic_data.csv ] ]

    main:
    BIOC_MSQUALITY_CHROMATOGRAPHIC_QC_CHROMATOGRAMS(ch_input)

    emit:
    tables   = BIOC_MSQUALITY_CHROMATOGRAPHIC_QC_CHROMATOGRAMS.out.tables
    plots    = BIOC_MSQUALITY_CHROMATOGRAPHIC_QC_CHROMATOGRAMS.out.plots
    objects  = BIOC_MSQUALITY_CHROMATOGRAPHIC_QC_CHROMATOGRAMS.out.objects
    versions = BIOC_MSQUALITY_CHROMATOGRAPHIC_QC_CHROMATOGRAMS.out.versions
}
