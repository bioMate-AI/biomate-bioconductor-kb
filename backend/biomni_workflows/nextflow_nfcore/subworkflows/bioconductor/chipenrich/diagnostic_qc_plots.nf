#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipenrich — diagnostic_qc_plots
// Generate quality control plots to visualize peak distance to TSS, peak presence/count versus locus length, or gene coverage.
// Input: peaks_E2F4, peaks_H3K4me3_GM12878
// Container: quay.io/biocontainers/bioconductor-chipenrich:2.34.0--r45hdfd78af_0
// R packages: chipenrich
// Bioconductor: 3.20 | R: 4.4
// Requires: chipenrich
// Visualizations: enrichment plot, coverage plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot peak distance to TSS distribution
//  * 2. [Visualization & Output] Plot presence of peak versus locus length spline
//  * 3. [Visualization & Output] Plot number of peaks versus locus length spline
//  * 4. [Visualization & Output] Plot gene coverage versus locus length

nextflow.enable.dsl = 2

process BIOC_CHIPENRICH_DIAGNOSTIC_QC_PLOTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("chipenrich")
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
    
    # Load required library
    library(chipenrich)
    
    # Helper function to find input files in the working directory
    find_file <- function(base_name) {
      if (file.exists(base_name)) {
        return(base_name)
      }
      files <- list.files(pattern = paste0("^", base_name, "(\\\\..+)?\$"))
      if (length(files) == 0) {
        stop(paste("Required input file not found in working directory:", base_name))
      }
      return(files[1])
    }
    
    # Helper function to read peak files into data.frames robustly
    read_peaks <- function(filename) {
      # Read table, ignoring lines starting with '#'
      df <- read.table(filename, header = FALSE, comment.char = "#", stringsAsFactors = FALSE, fill = TRUE)
      # Check if the first row contains header-like strings
      if (any(c("chrom", "chromStart", "start", "chromEnd", "end") %in% as.character(df[1, ]))) {
        df <- read.table(filename, header = TRUE, comment.char = "#", stringsAsFactors = FALSE, fill = TRUE)
      }
      # Ensure the first three columns are named chrom, start, end
      colnames(df)[1:3] <- c("chrom", "start", "end")
      return(df)
    }
    
    # Locate and read the user input files
    peaks_E2F4_file <- find_file("peaks_E2F4")
    peaks_H3K4me3_GM12878_file <- find_file("peaks_H3K4me3_GM12878")
    
    peaks_E2F4 <- read_peaks(peaks_E2F4_file)
    peaks_H3K4me3_GM12878 <- read_peaks(peaks_H3K4me3_GM12878_file)
    
    # --- Plot peak distance to TSS distribution ---
    pdf("plot_dist_to_tss.pdf", width = 6, height = 6)
    p1 <- plot_dist_to_tss(peaks = peaks_E2F4, genome = 'hg19')
    if (!is.null(p1)) print(p1)
    dev.off()
    
    # --- Plot presence of peak versus locus length spline ---
    pdf("plot_chipenrich_spline.pdf", width = 6, height = 6)
    p2 <- plot_chipenrich_spline(peaks = peaks_E2F4, locusdef = 'nearest_tss', genome = 'hg19')
    if (!is.null(p2)) print(p2)
    dev.off()
    
    # --- Plot number of peaks versus locus length spline ---
    pdf("plot_polyenrich_spline.pdf", width = 6, height = 6)
    p3 <- plot_polyenrich_spline(peaks = peaks_E2F4, locusdef = 'nearest_tss', genome = 'hg19')
    if (!is.null(p3)) print(p3)
    dev.off()
    
    # --- Plot gene coverage versus locus length ---
    pdf("plot_gene_coverage.pdf", width = 6, height = 6)
    p4 <- plot_gene_coverage(peaks = peaks_H3K4me3_GM12878, locusdef = 'nearest_tss',  genome = 'hg19')
    if (!is.null(p4)) print(p4)
    dev.off()
    
    message("Pipeline completed successfully. QC plots saved to working directory.")

    writeLines(c(
        '"BIOC_CHIPENRICH_DIAGNOSTIC_QC_PLOTS":',
        paste0('    chipenrich: ', as.character(packageVersion('chipenrich')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diagnostic_qc_plots.csv versions.yml
    """
}

workflow BIOC_CHIPENRICH_DIAGNOSTIC_QC_PLOTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks_E2F4, peaks_H3K4me3_GM12878 ] ]

    main:
    BIOC_CHIPENRICH_DIAGNOSTIC_QC_PLOTS(ch_input)

    emit:
    tables   = BIOC_CHIPENRICH_DIAGNOSTIC_QC_PLOTS.out.tables
    plots    = BIOC_CHIPENRICH_DIAGNOSTIC_QC_PLOTS.out.plots
    objects  = BIOC_CHIPENRICH_DIAGNOSTIC_QC_PLOTS.out.objects
    versions = BIOC_CHIPENRICH_DIAGNOSTIC_QC_PLOTS.out.versions
}
