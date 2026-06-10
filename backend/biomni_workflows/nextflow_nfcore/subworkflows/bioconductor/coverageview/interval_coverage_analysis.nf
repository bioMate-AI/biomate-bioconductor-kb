#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CoverageView — interval_coverage_analysis
// Calculate coverage ratios or values for a specific genomic interval (e.g., a single chromosome or coordinate range) and export the result to a WIG file.
// Input: H3K4me3.chr19.bam, H3K4me3_Control.chr19.bam
// Container: quay.io/biocontainers/bioconductor-coverageview:1.48.0--r45hdfd78af_0
// Requires: CoverageView, Rsamtools
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Instantiate CoverageBamFile objects for the sample and control
//  * 2. [Core Analysis] Calculate coverage ratios or values for a specific genomic interval using cov.interval
//  * 3. [Visualization & Output] Export the resulting coverage vector to a WIG file using export.wig

nextflow.enable.dsl = 2

process BIOC_COVERAGEVIEW_INTERVAL_COVERAGE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("CoverageView", "Rsamtools")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        # Load required libraries
        library(CoverageView)
        library(Rsamtools)
        
        # Define input file paths
        bam_treatment <- "./H3K4me3.chr19.bam"
        bam_control <- "./H3K4me3_Control.chr19.bam"
        
        # Verify input files exist
        if (!file.exists(bam_treatment)) {
          stop(paste("Required input file missing:", bam_treatment))
        }
        if (!file.exists(bam_control)) {
          stop(paste("Required input file missing:", bam_control))
        }
        
        # Ensure BAM index files (.bai) exist in the same directory, as required by CoverageView
        if (!file.exists(paste0(bam_treatment, ".bai"))) {
          message("Indexing treatment BAM file...")
          Rsamtools::indexBam(bam_treatment)
        }
        if (!file.exists(paste0(bam_control, ".bai"))) {
          message("Indexing control BAM file...")
          Rsamtools::indexBam(bam_control)
        }
        
        # 1. Instantiate CoverageBamFile objects for the sample and control
        trm<-CoverageBamFile(bam_treatment)
        ctl<-CoverageBamFile(bam_control)
        
        # 2. Calculate coverage ratios or values for a specific genomic interval using cov.interval
        chr19_246050_247000.ratios=cov.interval(trm,ctl,bin_width=1,chr="chr19",start=246050,end=247000,do='ratio')
        
        # 3. Export the resulting coverage vector to a WIG file using export.wig
        export.wig(chr19_246050_247000.ratios,outfile="chr19_246050_247000.ratios.wig")
        
        # Calculate coverage ratios for the entire chromosome 19
        chr19.ratios=cov.interval(trm,ctl,bin_width=1,chr="chr19",do='ratio')
        
        # Save the resulting R objects as RDS files for downstream analysis
        saveRDS(chr19_246050_247000.ratios, file="chr19_246050_247000_ratios.rds")
        saveRDS(chr19.ratios, file="chr19_ratios.rds")
        
        message("Pipeline completed successfully. Outputs generated:")
        message("- chr19_246050_247000.ratios.wig")
        message("- chr19_246050_247000_ratios.rds")
        message("- chr19_ratios.rds")

    writeLines(c(
        '"BIOC_COVERAGEVIEW_INTERVAL_COVERAGE_ANALYSIS":',
        paste0('    CoverageView: ', as.character(packageVersion('CoverageView')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interval_coverage_analysis.csv versions.yml
    """
}

workflow BIOC_COVERAGEVIEW_INTERVAL_COVERAGE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ H3K4me3.chr19.bam, H3K4me3_Control.chr19.bam ] ]

    main:
    BIOC_COVERAGEVIEW_INTERVAL_COVERAGE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_COVERAGEVIEW_INTERVAL_COVERAGE_ANALYSIS.out.tables
    plots    = BIOC_COVERAGEVIEW_INTERVAL_COVERAGE_ANALYSIS.out.plots
    objects  = BIOC_COVERAGEVIEW_INTERVAL_COVERAGE_ANALYSIS.out.objects
    versions = BIOC_COVERAGEVIEW_INTERVAL_COVERAGE_ANALYSIS.out.versions
}
