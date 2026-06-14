#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: coverageview — single_sample_coverage_profile
// Calculate and visualize coverage profiles and heatmaps around specific genomic coordinates (e.g., TSS) for a single BAM or BigWIG sample.
// Input: FoxA1.chr19.bam, FoxA1.chr19.bam.bai, FoxA1.chr19.bed
// Container: quay.io/biocontainers/bioconductor-coverageview:1.48.0--r45hdfd78af_0
// R packages: CoverageView
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: heatmap

nextflow.enable.dsl = 2

process BIOC_COVERAGEVIEW_SINGLE_SAMPLE_COVERAGE_PROFILE {
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
    
    # Load the required library
    library(CoverageView)
    
    # Define the input file paths (must exist in the working directory)
    bam_file <- "./FoxA1.chr19.bam"
    bai_file <- "./FoxA1.chr19.bam.bai"
    tss_chr19_bed <- "./FoxA1.chr19.bed"
    
    # Verify that the required input files exist before proceeding
    if (!file.exists(bam_file)) {
      stop(paste("Required BAM file not found:", bam_file))
    }
    if (!file.exists(bai_file)) {
      stop(paste("Required BAM index file not found:", bai_file))
    }
    if (!file.exists(tss_chr19_bed)) {
      stop(paste("Required BED file not found:", tss_chr19_bed))
    }
    
    # --- Instantiate CoverageBamFile object ---
    trm <- CoverageBamFile(bam_file, reads_mapped=168042)
    
    # --- Calculate coverage matrix around coordinates ---
    FoxA1_chr19 <- cov.matrix(trm, coordfile=tss_chr19_bed, extend=1000, num_cores=2, bin_width=10)
    
    # --- Draw coverage profile ---
    draw.profile(FoxA1_chr19, ylab="avg coverage", outfile="FoxA1_chr19.png", main="FoxA1 chr19")
    
    # --- Write coverage matrix to file ---
    write.profile(FoxA1_chr19, outfile="FoxA1_chr19.txt")
    
    # --- Draw coverage heatmap ---
    draw.heatmap(FoxA1_chr19, outfile="FoxA1_chr19_heatmap.png")

    writeLines(c(
        '"BIOC_COVERAGEVIEW_SINGLE_SAMPLE_COVERAGE_PROFILE":',
        paste0('        coverageview: ', as.character(packageVersion("coverageview")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_coverage_profile.csv versions.yml
    """
}

workflow BIOC_COVERAGEVIEW_SINGLE_SAMPLE_COVERAGE_PROFILE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ FoxA1.chr19.bam, FoxA1.chr19.bam.bai, FoxA1.chr19.bed ] ]

    main:
    BIOC_COVERAGEVIEW_SINGLE_SAMPLE_COVERAGE_PROFILE(ch_input)

    emit:
    tables   = BIOC_COVERAGEVIEW_SINGLE_SAMPLE_COVERAGE_PROFILE.out.tables
    plots    = BIOC_COVERAGEVIEW_SINGLE_SAMPLE_COVERAGE_PROFILE.out.plots
    objects  = BIOC_COVERAGEVIEW_SINGLE_SAMPLE_COVERAGE_PROFILE.out.objects
    versions = BIOC_COVERAGEVIEW_SINGLE_SAMPLE_COVERAGE_PROFILE.out.versions
}
