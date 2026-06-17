#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipseeker — peak_profiling_and_visualization
// Profile and visualize ChIP peak binding distributions around TSS or gene body regions using heatmaps and average profiles.
// Input: files[[4]], txdb
// Container: quay.io/biocontainers/bioconductor-chipseeker:1.46.1--r45hdfd78af_0
// R packages: ChIPseeker, clusterProfiler, GenomicFeatures, GenomicRanges, ggplot2, ReactomePA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPSEEKER_PEAK_PROFILING_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chipseeker:1.46.1--r45hdfd78af_0"

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
    .bm_deps <- c("ChIPseeker", "clusterProfiler", "GenomicFeatures", "GenomicRanges", "ggplot2", "ReactomePA")
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
    library(ChIPseeker)
    library(GenomicFeatures)
    library(ggplot2)
    
    # --- Locate the BED file in the working directory ---
    # The user specified files[[4]] is the BED file.
    # We search for any BED file in the current directory to populate files[[4]].
    bed_files <- list.files(pattern = "\\\\.(bed|BED)(\\\\.gz)?\$")
    if (length(bed_files) == 0) {
      stop("Error: No BED file found in the working directory.")
    }
    files <- list(NULL, NULL, NULL, bed_files[1])
    
    # --- Load the TxDb object ---
    # The user specified 'txdb' is a TxDb object. We read it from 'txdb.rds' in the working directory.
    if (!file.exists("txdb.rds")) {
      stop("Error: txdb.rds not found in the working directory.")
    }
    txdb <- readRDS("txdb.rds")
    
    # --- Read peak file ---
    message("Reading peak file...")
    peak <- readPeakFile(files[[4]])
    saveRDS(peak, "peak_object.rds")
    
    # --- Plot peak coverage over chromosomes ---
    message("Generating coverage plots...")
    pdf("covplot_all.pdf", width = 10, height = 8)
    print(covplot(peak, weightCol="V5"))
    dev.off()
    
    # Optional subset coverage plot (wrapped in tryCatch in case chr17/18 are absent or named differently in user data)
    tryCatch({
      pdf("covplot_subset.pdf", width = 10, height = 4)
      print(covplot(peak, weightCol="V5", chrs=c("chr17", "chr18"), xlim=c(4.5e7, 5e7)))
      dev.off()
    }, error = function(e) {
      warning("Could not generate subset covplot: ", e\$message)
    })
    
    # --- Retrieve tag matrix around genomic regions ---
    message("Calculating tag matrix...")
    promoter <- getPromoters(TxDb=txdb, upstream=3000, downstream=3000)
    tagMatrix <- getTagMatrix(peak, windows=promoter)
    saveRDS(tagMatrix, "tagMatrix.rds")
    
    # --- Generate heatmaps of peak binding ---
    message("Generating heatmaps...")
    pdf("tagHeatmap.pdf", width = 6, height = 9)
    tagHeatmap(tagMatrix)
    dev.off()
    
    pdf("peakHeatmap.pdf", width = 6, height = 9)
    peakHeatmap(peak = files[[4]], TxDb = txdb, upstream = rel(0.2), downstream = rel(0.2), by = "gene", type = "body", nbin = 800)
    dev.off()
    
    # --- Plot average profiles of peak binding ---
    message("Generating average profiles...")
    pdf("plotAvgProf.pdf", width = 7, height = 4)
    print(plotAvgProf(tagMatrix, xlim=c(-3000, 3000), xlab="Genomic Region (5'->3')", ylab = "Read Count Frequency"))
    dev.off()
    
    pdf("plotPeakProf2.pdf", width = 7, height = 4)
    print(plotPeakProf2(peak = peak, upstream = rel(0.2), downstream = rel(0.2), conf = 0.95, by = "gene", type = "body", nbin = 800, TxDb = txdb, weightCol = "V5", ignore_strand = F))
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_CHIPSEEKER_PEAK_PROFILING_AND_VISUALIZATION":',
        paste0('        chipseeker: ', as.character(packageVersion("chipseeker")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peak_profiling_and_visualization.csv versions.yml
    """
}

workflow BIOC_CHIPSEEKER_PEAK_PROFILING_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files[[4]], txdb ] ]

    main:
    BIOC_CHIPSEEKER_PEAK_PROFILING_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_CHIPSEEKER_PEAK_PROFILING_AND_VISUALIZATION.out.tables
    plots    = BIOC_CHIPSEEKER_PEAK_PROFILING_AND_VISUALIZATION.out.plots
    objects  = BIOC_CHIPSEEKER_PEAK_PROFILING_AND_VISUALIZATION.out.objects
    versions = BIOC_CHIPSEEKER_PEAK_PROFILING_AND_VISUALIZATION.out.versions
}
