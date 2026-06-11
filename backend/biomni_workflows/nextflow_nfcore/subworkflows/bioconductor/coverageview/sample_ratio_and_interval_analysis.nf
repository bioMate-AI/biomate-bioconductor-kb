#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: coverageview — sample_ratio_and_interval_analysis
// Calculate coverage ratios, log2ratios, or subtractions between two samples across genomic regions or a specific coordinate interval, and export the results.
// Input: H3K4me3.chr19.bam, H3K4me3_Control.chr19.bam, H3K4me3.chr19.nopeaks.bed
// Container: quay.io/biocontainers/bioconductor-coverageview:1.48.0--r45hdfd78af_0
// R packages: CoverageView
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COVERAGEVIEW_SAMPLE_RATIO_AND_INTERVAL_ANALYSIS {
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
    
    # Load the required Bioconductor library
    library(CoverageView)
    
    # Define the input file paths from the working directory
    trm_bam <- "./H3K4me3.chr19.bam"
    ctl_bam <- "./H3K4me3_Control.chr19.bam"
    H3K4me3_chr19_nopeaks_bed <- "./H3K4me3.chr19.nopeaks.bed"
    
    # 1. Instantiate CoverageBamFile objects
    trm <- CoverageBamFile(trm_bam, reads_mapped=864924)
    ctl <- CoverageBamFile(ctl_bam, reads_mapped=319369)
    
    # 2. Calculate log2ratio coverage matrix across BED coordinates
    DF_H3K4me3_nopeaks_ratios = cov.matrix(trm, ctl, coordfile=H3K4me3_chr19_nopeaks_bed, no_windows=100, offset=10, num_cores=2, normalization="rpm", do="log2ratio")
    
    # Save the calculated matrix to RDS and CSV formats
    saveRDS(DF_H3K4me3_nopeaks_ratios, file="DF_H3K4me3_nopeaks_ratios.rds")
    write.csv(as.data.frame(DF_H3K4me3_nopeaks_ratios), file="DF_H3K4me3_nopeaks_ratios.csv", row.names=FALSE)
    
    # 3. Draw ratio profile
    draw.profile(DF_H3K4me3_nopeaks_ratios, ylab="avg coverage", outfile="H3K4me3nopeaks_ratios.png", main="H3K4me3 ratio")
    
    # 4. Calculate ratio across a specific genomic interval
    chr19_246050_247000.ratios = cov.interval(trm, ctl, bin_width=1, chr="chr19", start=246050, end=247000, do='ratio')
    
    # Save the interval ratios to an RDS file
    saveRDS(chr19_246050_247000.ratios, file="chr19_246050_247000_ratios.rds")
    
    # 5. Export interval ratios to WIG format
    export.wig(chr19_246050_247000.ratios, outfile="chr19_246050_247000.ratios.wig")

    writeLines(c(
        '"BIOC_COVERAGEVIEW_SAMPLE_RATIO_AND_INTERVAL_ANALYSIS":',
        paste0('        coverageview: ', as.character(packageVersion("coverageview")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sample_ratio_and_interval_analysis.csv versions.yml
    """
}

workflow BIOC_COVERAGEVIEW_SAMPLE_RATIO_AND_INTERVAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ H3K4me3.chr19.bam, H3K4me3_Control.chr19.bam, H3K4me3.chr19.nopeaks.bed ] ]

    main:
    BIOC_COVERAGEVIEW_SAMPLE_RATIO_AND_INTERVAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_COVERAGEVIEW_SAMPLE_RATIO_AND_INTERVAL_ANALYSIS.out.tables
    plots    = BIOC_COVERAGEVIEW_SAMPLE_RATIO_AND_INTERVAL_ANALYSIS.out.plots
    objects  = BIOC_COVERAGEVIEW_SAMPLE_RATIO_AND_INTERVAL_ANALYSIS.out.objects
    versions = BIOC_COVERAGEVIEW_SAMPLE_RATIO_AND_INTERVAL_ANALYSIS.out.versions
}
