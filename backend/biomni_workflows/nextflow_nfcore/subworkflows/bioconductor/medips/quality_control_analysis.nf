#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MEDIPS — quality_control_analysis
// Perform quality control checks on MeDIP-seq or ChIP-seq data, including saturation analysis, sequence pattern coverage, and CpG enrichment.
// Input: bam.file.hESCs.Rep1.MeDIP
// Container: quay.io/biocontainers/bioconductor-medips:1.62.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, MEDIPS
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, MEDIPS
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run saturation analysis using MEDIPS.saturation and plot using MEDIPS.plotSaturation
//  * 2. [Visualization & Output] Run sequence pattern coverage analysis using MEDIPS.seqCoverage and plot using MEDIPS.plotSeqCoverage
//  * 3. [Core Analysis] Calculate CpG enrichment using MEDIPS.CpGenrich

nextflow.enable.dsl = 2

process BIOC_MEDIPS_QUALITY_CONTROL_ANALYSIS {
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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "MEDIPS")
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
        
        # Load required libraries
        library(MEDIPS)
        library(BSgenome.Hsapiens.UCSC.hg19)
        
        # Define the input file from the working directory
        bam.file.hESCs.Rep1.MeDIP <- "bam.file.hESCs.Rep1.MeDIP"
        
        # Define parameters as specified in the documentation
        BSgenome <- "BSgenome.Hsapiens.UCSC.hg19"
        uniq <- 1e-3
        extend <- 300
        shift <- 0
        ws <- 100
        
        # 1. Run saturation analysis and plot
        sr <- MEDIPS.saturation(
          file = bam.file.hESCs.Rep1.MeDIP,
          BSgenome = BSgenome,
          uniq = uniq,
          extend = extend,
          shift = shift,
          window_size = ws,
          nit = 10,
          nrit = 1,
          empty_bins = TRUE,
          rank = FALSE
        )
        
        # Save saturation plot to PDF
        pdf("saturation_plot.pdf", width = 7, height = 7)
        MEDIPS.plotSaturation(sr)
        dev.off()
        
        # Save saturation results object
        saveRDS(sr, "saturation_results.rds")
        
        
        # 2. Run sequence pattern coverage analysis and plot
        cr <- MEDIPS.seqCoverage(
          file = bam.file.hESCs.Rep1.MeDIP,
          pattern = "CG",
          BSgenome = BSgenome,
          extend = extend,
          shift = shift,
          uniq = uniq
        )
        
        # Save sequence coverage pie chart to PDF
        pdf("seq_coverage_pie.pdf", width = 7, height = 7)
        MEDIPS.plotSeqCoverage(seqCoverageObj = cr, type = "pie", cov.level = c(0, 1, 2, 3, 4, 5))
        dev.off()
        
        # Save sequence coverage histogram to PDF
        pdf("seq_coverage_hist.pdf", width = 7, height = 7)
        MEDIPS.plotSeqCoverage(seqCoverageObj = cr, type = "hist", t = 15, main = "Sequence pattern coverage, histogram")
        dev.off()
        
        # Save sequence coverage results object
        saveRDS(cr, "seq_coverage_results.rds")
        
        
        # 3. Calculate CpG enrichment
        er <- MEDIPS.CpGenrich(
          file = bam.file.hESCs.Rep1.MeDIP,
          BSgenome = BSgenome,
          extend = extend,
          shift = shift,
          uniq = uniq
        )
        
        # Save CpG enrichment results object
        saveRDS(er, "cpg_enrichment_results.rds")
        
        # Export CpG enrichment summary text
        sink("cpg_enrichment_summary.txt")
        print(er)
        sink()

    writeLines(c(
        '"BIOC_MEDIPS_QUALITY_CONTROL_ANALYSIS":',
        paste0('    MEDIPS: ', as.character(packageVersion('MEDIPS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quality_control_analysis.csv versions.yml
    """
}

workflow BIOC_MEDIPS_QUALITY_CONTROL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam.file.hESCs.Rep1.MeDIP ] ]

    main:
    BIOC_MEDIPS_QUALITY_CONTROL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MEDIPS_QUALITY_CONTROL_ANALYSIS.out.tables
    plots    = BIOC_MEDIPS_QUALITY_CONTROL_ANALYSIS.out.plots
    objects  = BIOC_MEDIPS_QUALITY_CONTROL_ANALYSIS.out.objects
    versions = BIOC_MEDIPS_QUALITY_CONTROL_ANALYSIS.out.versions
}
