#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: coverageview — multi_sample_comparison
// Compare normalized coverage profiles and heatmaps across gene bodies between multiple samples (e.g., ChIP-seq treatment vs. control).
// Input: H3K4me3.chr19.bam, H3K4me3_Control.chr19.bam, H3K4me3.chr19.bed
// Container: quay.io/biocontainers/bioconductor-coverageview:1.48.0--r45hdfd78af_0
// R packages: CoverageView
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: heatmap

nextflow.enable.dsl = 2

process BIOC_COVERAGEVIEW_MULTI_SAMPLE_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-coverageview:1.48.0--r45hdfd78af_0"

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
    .bm_deps <- c("CoverageView")
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
    library(CoverageView)
    
    # Define input file paths from the working directory
    bam_treatment <- "./H3K4me3.chr19.bam"
    bam_control <- "./H3K4me3_Control.chr19.bam"
    H3K4me3_chr19_bed <- "./H3K4me3.chr19.bed"
    
    # Verify input files exist before running the pipeline
    if (!file.exists(bam_treatment)) {
      stop(paste("Required treatment BAM file not found:", bam_treatment))
    }
    if (!file.exists(bam_control)) {
      stop(paste("Required control BAM file not found:", bam_control))
    }
    if (!file.exists(H3K4me3_chr19_bed)) {
      stop(paste("Required BED file not found:", H3K4me3_chr19_bed))
    }
    
    # --- Instantiate CoverageBamFile objects for treatment and ---
    trm <- CoverageBamFile(bam_treatment, reads_mapped=864924)
    ctl <- CoverageBamFile(bam_control, reads_mapped=319369)
    
    # --- Calculate normalized coverage matrices across gene windows ---
    DF_H3K4me3 <- cov.matrix(trm, coordfile=H3K4me3_chr19_bed, no_windows=100, offset=10, num_cores=2, normalization="rpm")
    DF_H3K4me3_ctl <- cov.matrix(ctl, coordfile=H3K4me3_chr19_bed, no_windows=100, offset=10, num_cores=2, normalization="rpm")
    
    # Save the calculated matrices as RDS and CSV files for downstream analysis
    saveRDS(DF_H3K4me3, file="DF_H3K4me3.rds")
    saveRDS(DF_H3K4me3_ctl, file="DF_H3K4me3_ctl.rds")
    write.csv(as.data.frame(DF_H3K4me3), file="DF_H3K4me3.csv", row.names=FALSE)
    write.csv(as.data.frame(DF_H3K4me3_ctl), file="DF_H3K4me3_ctl.csv", row.names=FALSE)
    
    # --- Combine matrices into a list ---
    input_list = list(DF_H3K4me3, DF_H3K4me3_ctl) 
    
    # --- Draw comparative profile ---
    draw.profile(data=input_list, ylab="avg coverage", outfile="H3K4me3cmp.png", main="H3K4me3")
    
    # --- Draw comparative heatmap ---
    draw.heatmap(data=input_list, outfile="H3K4me3cmp_heatmap.png")

    writeLines(c(
        '"BIOC_COVERAGEVIEW_MULTI_SAMPLE_COMPARISON":',
        paste0('        coverageview: ', as.character(packageVersion("coverageview")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_sample_comparison.csv versions.yml
    """
}

workflow BIOC_COVERAGEVIEW_MULTI_SAMPLE_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ H3K4me3.chr19.bam, H3K4me3_Control.chr19.bam, H3K4me3.chr19.bed ] ]

    main:
    BIOC_COVERAGEVIEW_MULTI_SAMPLE_COMPARISON(ch_input)

    emit:
    tables   = BIOC_COVERAGEVIEW_MULTI_SAMPLE_COMPARISON.out.tables
    plots    = BIOC_COVERAGEVIEW_MULTI_SAMPLE_COMPARISON.out.plots
    objects  = BIOC_COVERAGEVIEW_MULTI_SAMPLE_COMPARISON.out.objects
    versions = BIOC_COVERAGEVIEW_MULTI_SAMPLE_COMPARISON.out.versions
}
